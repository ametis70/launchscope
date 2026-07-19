// Package cec provides HDMI-CEC control via the launchscope-cec bridge socket.
// The launchscope-cec service maintains a persistent libcec connection and
// exposes a Unix socket at /run/launchscope-cec/cmd.sock for command injection.
package cec

import (
	"fmt"
	"net"
	"sync"
	"time"
)

const socketPath = "/run/launchscope-cec/cmd.sock"
const activateThrottle = 3 * time.Second

// State holds the last-known CEC device state pushed by cec-uinput.
type State struct {
	TVOn           bool  `json:"tv_on"`
	AVROn          *bool `json:"avr_on"`           // nil when no AVR configured
	ActiveSource   *int  `json:"active_source"`    // logical addr, nil when unknown
	IsActiveSource bool  `json:"is_active_source"` // active_source == own logical addr (1)
}

// Client sends CEC commands via the launchscope-cec Unix socket and stores
// the last-known CEC state pushed by the bridge.
type Client struct {
	mu           sync.Mutex
	lastActivate time.Time
	stateMu      sync.RWMutex
	state        State
}

// New creates a CEC client.
func New() *Client { return &Client{} }

// GetState returns the last-known CEC state.
func (c *Client) GetState() State {
	c.stateMu.RLock()
	defer c.stateMu.RUnlock()
	return c.state
}

// SetState replaces the stored CEC state.
func (c *Client) SetState(s State) {
	c.stateMu.Lock()
	defer c.stateMu.Unlock()
	c.state = s
}

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
		return fmt.Errorf("cannot connect to launchscope-cec socket %s: %w", socketPath, err)
	}
	defer conn.Close() //nolint:errcheck
	if err := conn.SetDeadline(time.Now().Add(5 * time.Second)); err != nil {
		return fmt.Errorf("setting deadline on cec socket: %w", err)
	}
	if _, err := fmt.Fprintf(conn, "%s\n", cmd); err != nil {
		return fmt.Errorf("sending command %q: %w", cmd, err)
	}
	return nil
}
