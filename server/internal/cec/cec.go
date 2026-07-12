// Package cec provides HDMI-CEC control via the cec-uinput bridge socket.
// The cec-uinput service maintains a persistent cec-client connection and
// exposes a Unix socket at /run/cec-uinput/cmd.sock for command injection.
package cec

import (
	"fmt"
	"net"
	"time"
)

const socketPath = "/run/cec-uinput/cmd.sock"

// Client sends CEC commands via the cec-uinput Unix socket.
type Client struct{}

// New creates a CEC client.
func New() *Client { return &Client{} }

// Activate powers on the TV and switches it to this device's HDMI input.
func (c *Client) Activate() error { return c.send("activate") }

// Standby sends the TV to standby (power off).
func (c *Client) Standby() error { return c.send("standby") }

// SwitchInput tells the TV to switch to a specific HDMI port (1-based).
func (c *Client) SwitchInput(port int) error {
	if port < 1 || port > 15 {
		return fmt.Errorf("invalid HDMI port %d (must be 1–15)", port)
	}
	return c.send(fmt.Sprintf("switch:%d", port))
}

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
