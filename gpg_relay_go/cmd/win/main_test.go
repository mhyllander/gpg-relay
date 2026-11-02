package main

import (
	"context"
	"io"
	"log/slog"
	"net"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
	"time"
)

func TestNonceAuthenticationAndAssuanForwarding(t *testing.T) {
	dir := t.TempDir()
	agent, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer agent.Close()
	agentNonce := strings.Repeat("a", 16)
	path := filepath.Join(dir, "assuan")
	os.WriteFile(path, []byte(strconv.Itoa(agent.Addr().(*net.TCPAddr).Port)+"\n"+agentNonce), 0600)
	bin := filepath.Join(dir, "bin")
	os.Mkdir(bin, 0755)
	os.WriteFile(filepath.Join(bin, "gpgconf.exe"), []byte("#!/bin/sh\necho '"+path+"'\n"), 0755)
	t.Setenv("PATH", bin+":"+os.Getenv("PATH"))
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer listener.Close()
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go serve(ctx, listener, "agent-socket", []byte(strings.Repeat("b", 16)), slog.Default())
	wrong, err := net.Dial("tcp", listener.Addr().String())
	if err != nil {
		t.Fatal(err)
	}
	wrong.SetDeadline(time.Now().Add(3 * time.Second))
	wrong.Write([]byte(strings.Repeat("x", 16)))
	single := make([]byte, 1)
	_, err = wrong.Read(single)
	wrong.Close()
	if err != io.EOF {
		t.Fatalf("wrong nonce connection: %v", err)
	}
	done := make(chan error, 1)
	go func() {
		peer, err := agent.Accept()
		if err != nil {
			done <- err
			return
		}
		defer peer.Close()
		peer.SetDeadline(time.Now().Add(3 * time.Second))
		first := make([]byte, 16)
		_, err = io.ReadFull(peer, first)
		if err != nil {
			done <- err
			return
		}
		if string(first) != agentNonce {
			done <- io.ErrUnexpectedEOF
			return
		}
		request, err := io.ReadAll(peer)
		if err != nil {
			done <- err
			return
		}
		if string(request) != "request" {
			done <- io.ErrUnexpectedEOF
			return
		}
		_, err = peer.Write([]byte("response"))
		done <- err
	}()
	client, err := net.Dial("tcp", listener.Addr().String())
	if err != nil {
		t.Fatal(err)
	}
	defer client.Close()
	client.SetDeadline(time.Now().Add(3 * time.Second))
	client.Write([]byte(strings.Repeat("b", 16) + "request"))
	client.(*net.TCPConn).CloseWrite()
	response, err := io.ReadAll(client)
	if err != nil || string(response) != "response" {
		t.Fatalf("response %q: %v", response, err)
	}
	if err := <-done; err != nil {
		t.Fatal(err)
	}
}

func TestWarnLimiterSuppressesRepeats(t *testing.T) {
	var buf strings.Builder
	log := slog.New(slog.NewTextHandler(&buf, nil))
	limiter := &warnLimiter{interval: time.Hour}
	for i := 0; i < 5; i++ {
		limiter.warn(log, "incorrect nonce")
	}
	if n := strings.Count(buf.String(), "incorrect nonce"); n != 1 {
		t.Fatalf("logged %d times, want 1", n)
	}
	limiter.last = time.Now().Add(-2 * time.Hour)
	limiter.warn(log, "incorrect nonce")
	if !strings.Contains(buf.String(), "suppressed=4") {
		t.Fatalf("missing suppressed count in %q", buf.String())
	}
}

func TestConnectionLimit(t *testing.T) {
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer listener.Close()
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go serve(ctx, listener, "agent-socket", []byte(strings.Repeat("b", 16)), slog.Default())
	// Idle connections hold their slots while the server waits for a nonce.
	var held []net.Conn
	for i := 0; i < maxConnections; i++ {
		c, err := net.Dial("tcp", listener.Addr().String())
		if err != nil {
			t.Fatal(err)
		}
		held = append(held, c)
	}
	defer func() {
		for _, c := range held {
			c.Close()
		}
	}()
	extra, err := net.Dial("tcp", listener.Addr().String())
	if err != nil {
		t.Fatal(err)
	}
	defer extra.Close()
	extra.SetReadDeadline(time.Now().Add(3 * time.Second))
	if _, err := extra.Read(make([]byte, 1)); err != io.EOF {
		t.Fatalf("over-limit connection: %v, want EOF", err)
	}
}
