// Package cec provides HDMI-CEC control via the cec-uinput bridge socket.
// The cec-uinput service maintains a persistent cec-client connection and
// exposes a Unix socket at /run/cec-uinput/cmd.sock for command injection.
package cec

import (
	"fmt"
	"net"
	"sync"
	"time"
)

const socketPath = "/run/cec-uinput/cmd.sock"
const activateThrottle = 3 * time.Second

// Client sends CEC commands via the cec-uinput Unix socket.
type Client struct {
	mu           sync.Mutex
	lastActivate time.Time
}

// New creates a CEC client.
func New() *Client { return &Client{} }

// Activate powers on TV + AVR, waits CEC_ACTIVATE_DELAY, then sets active
// source. Throttled — calls within activateThrottle are dropped to avoid
// queuing while the bridge is blocking on the delay.
func (c *Client) Activate() error {
	c.mu.Lock()
	if time.Since(c.lastActivate) < activateThrottle {
		c.mu.Unlock()
		return nil
	}
	c.lastActivate = time.Now()
	c.mu.Unlock()
	return c.send("activate")
}

// PowerOn powers on the TV and AVR without switching the active source.
func (c *Client) PowerOn() error { return c.send("power-on") }

// SetSource broadcasts ActiveSource with the configured physical address,
// switching the AVR input to the host PC.
func (c *Client) SetSource() error { return c.send("set-source") }

// Standby sends the AVR to standby.
func (c *Client) Standby() error { return c.send("standby") }

func (c *Client) send(cmd string) error {
	conn, err := net.DialTimeout("unix", socketPath, 3*time.Second)
	if err != nil {
		return fmt.Errorf("cannot connect to cec-uinput socket %s: %w", socketPath, err)
	}
	defer conn.Close()
	if err := conn.SetDeadline(time.Now().Add(5 * time.Second)); err != nil {
		return fmt.Errorf("setting deadline on cec socket: %w", err)
	}
	if _, err := fmt.Fprintf(conn, "%s\n", cmd); err != nil {
		return fmt.Errorf("sending command %q: %w", cmd, err)
	}
	return nil
}
