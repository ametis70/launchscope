package api

import (
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"

	"github.com/ametis70/launchscope/server/internal/apps"
	"github.com/ametis70/launchscope/server/internal/audio"
	"github.com/ametis70/launchscope/server/internal/cec"
	"github.com/ametis70/launchscope/server/internal/config"
	"github.com/ametis70/launchscope/server/internal/process"
	"github.com/ametis70/launchscope/server/internal/system"
)

type handlers struct {
	mgr        *process.Manager
	cfgLoader  *config.Loader
	appsLoader *apps.Loader
	log        *slog.Logger
}

// ── GET /api/status ─────────────────────────────────────────────────────── //

type statusResponse struct {
	State      process.State  `json:"state"`
	CurrentApp *appSummary    `json:"current_app"`
	Audio      *audioResponse `json:"audio"`
}

type appSummary struct {
	ID   string `json:"id"`
	Name string `json:"name"`
}

func (h *handlers) getStatus(w http.ResponseWriter, r *http.Request) {
	snap := h.mgr.Status()
	var cur *appSummary
	if snap.CurrentApp != nil {
		cur = &appSummary{ID: snap.CurrentApp.ID, Name: snap.CurrentApp.Name}
	}

	av, err := audio.GetVolume()
	var ar *audioResponse
	if err == nil {
		ar = &audioResponse{Volume: av.Volume, Muted: av.Muted, SinkName: av.SinkName}
	}

	jsonOK(w, statusResponse{
		State:      snap.State,
		CurrentApp: cur,
		Audio:      ar,
	})
}

// ── GET /api/apps ────────────────────────────────────────────────────────── //

func (h *handlers) getApps(w http.ResponseWriter, r *http.Request) {
	list := h.appsLoader.Current()
	summaries := make([]appSummary, len(list))
	for i, a := range list {
		summaries[i] = appSummary{ID: a.ID, Name: a.Name}
	}
	jsonOK(w, summaries)
}

// ── POST /api/launch/{id} ────────────────────────────────────────────────── //

func (h *handlers) postLaunch(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	if err := h.mgr.LaunchApp(id); err != nil {
		status := http.StatusInternalServerError
		if err.Error() == "no app with id \""+id+"\"" {
			status = http.StatusNotFound
		} else if errors.Is(err, process.ErrBusy) {
			status = http.StatusConflict
		}
		jsonError(w, err.Error(), status)
		return
	}
	w.WriteHeader(http.StatusAccepted)
}

// ── POST /api/stop ───────────────────────────────────────────────────────── //

func (h *handlers) postStop(w http.ResponseWriter, r *http.Request) {
	h.mgr.Stop()
	jsonOK(w, map[string]string{"state": string(process.StateStopping)})
}

// ── GET /api/audio ───────────────────────────────────────────────────────── //

type audioResponse struct {
	Volume   float64 `json:"volume"`
	Muted    bool    `json:"muted"`
	SinkName string  `json:"sink_name"`
}

func (h *handlers) getAudio(w http.ResponseWriter, r *http.Request) {
	st, err := audio.GetVolume()
	if err != nil {
		jsonError(w, err.Error(), http.StatusInternalServerError)
		return
	}
	jsonOK(w, audioResponse{Volume: st.Volume, Muted: st.Muted, SinkName: st.SinkName})
}

// ── POST /api/audio/volume ───────────────────────────────────────────────── //

type volumeRequest struct {
	Value *float64 `json:"value"`
	Delta *float64 `json:"delta"`
}

func (h *handlers) postAudioVolume(w http.ResponseWriter, r *http.Request) {
	var req volumeRequest
	if !decodeBody(w, r, &req) {
		return
	}
	var err error
	switch {
	case req.Value != nil:
		err = audio.SetVolume(*req.Value)
	case req.Delta != nil:
		err = audio.AdjustVolume(*req.Delta)
	default:
		jsonError(w, "body must contain 'value' or 'delta'", http.StatusBadRequest)
		return
	}
	if err != nil {
		jsonError(w, err.Error(), http.StatusInternalServerError)
		return
	}
	st, err := audio.GetVolume()
	if err != nil {
		jsonError(w, err.Error(), http.StatusInternalServerError)
		return
	}
	jsonOK(w, audioResponse{Volume: st.Volume, Muted: st.Muted, SinkName: st.SinkName})
}

// ── POST /api/audio/mute ─────────────────────────────────────────────────── //

type muteRequest struct {
	Muted  *bool `json:"muted"`
	Toggle *bool `json:"toggle"`
}

func (h *handlers) postAudioMute(w http.ResponseWriter, r *http.Request) {
	var req muteRequest
	if !decodeBody(w, r, &req) {
		return
	}
	var err error
	switch {
	case req.Toggle != nil && *req.Toggle:
		err = audio.ToggleMute()
	case req.Muted != nil:
		err = audio.SetMute(*req.Muted)
	default:
		jsonError(w, "body must contain 'muted' or 'toggle'", http.StatusBadRequest)
		return
	}
	if err != nil {
		jsonError(w, err.Error(), http.StatusInternalServerError)
		return
	}
	st, err := audio.GetVolume()
	if err != nil {
		jsonError(w, err.Error(), http.StatusInternalServerError)
		return
	}
	jsonOK(w, audioResponse{Volume: st.Volume, Muted: st.Muted, SinkName: st.SinkName})
}

// ── GET /api/config ──────────────────────────────────────────────────────── //
// Returns daemon config (API settings only — no UI fields, no apps).

func (h *handlers) getConfig(w http.ResponseWriter, r *http.Request) {
	cfg := *h.cfgLoader.Current()
	cfg.API.APIKey = "" // never expose the key over the wire
	jsonOK(w, cfg)
}

// ── POST /api/system/power ───────────────────────────────────────────────── //

type powerRequest struct {
	Action string `json:"action"`
}

func (h *handlers) postPower(w http.ResponseWriter, r *http.Request) {
	var req powerRequest
	if !decodeBody(w, r, &req) {
		return
	}
	if err := system.Run(system.Action(req.Action)); err != nil {
		jsonError(w, err.Error(), http.StatusBadRequest)
		return
	}
	w.WriteHeader(http.StatusAccepted)
}

// ── shared helpers ───────────────────────────────────────────────────────── //

func jsonOK(w http.ResponseWriter, v any) {
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(v)
}

func jsonError(w http.ResponseWriter, msg string, code int) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(map[string]string{"error": msg})
}

func decodeBody(w http.ResponseWriter, r *http.Request, dst any) bool {
	if err := json.NewDecoder(r.Body).Decode(dst); err != nil {
		jsonError(w, "invalid JSON: "+err.Error(), http.StatusBadRequest)
		return false
	}
	return true
}

// ── GET /api/cec/state ───────────────────────────────────────────────────── //

func makeCECGetStateHandler(c *cec.Client) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if c == nil {
			jsonError(w, "CEC is not enabled (set cec.enabled = true in config)", http.StatusServiceUnavailable)
			return
		}
		jsonOK(w, c.GetState())
	}
}

// ── POST /api/cec/state ──────────────────────────────────────────────────── //

func makeCECPostStateHandler(c *cec.Client, log *slog.Logger) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if c == nil {
			jsonError(w, "CEC is not enabled (set cec.enabled = true in config)", http.StatusServiceUnavailable)
			return
		}
		var s cec.State
		if !decodeBody(w, r, &s) {
			return
		}
		c.SetState(s)
		log.Debug("cec state updated", "tv_on", s.TVOn, "avr_on", s.AVROn, "active_source", s.ActiveSource, "is_active_source", s.IsActiveSource)
		w.WriteHeader(http.StatusNoContent)
	}
}

// makeCECActivateHandler powers on TV + AVR, waits, then sets active source.
func makeCECActivateHandler(c *cec.Client, log *slog.Logger) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if c == nil {
			jsonError(w, "CEC is not enabled (set cec.enabled = true in config)", http.StatusServiceUnavailable)
			return
		}
		if err := c.Activate(); err != nil {
			log.Error("cec activate failed", "err", err)
			jsonError(w, err.Error(), http.StatusInternalServerError)
			return
		}
		log.Info("cec activate: power-on + set-source sent")
		jsonOK(w, map[string]string{"status": "ok"})
	}
}

// ── POST /api/cec/power-on ───────────────────────────────────────────────── //

// makeCECPowerOnHandler powers on TV and AVR without switching the active source.
func makeCECPowerOnHandler(c *cec.Client, log *slog.Logger) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if c == nil {
			jsonError(w, "CEC is not enabled (set cec.enabled = true in config)", http.StatusServiceUnavailable)
			return
		}
		if err := c.PowerOn(); err != nil {
			log.Error("cec power-on failed", "err", err)
			jsonError(w, err.Error(), http.StatusInternalServerError)
			return
		}
		log.Info("cec power-on: TV + AVR powered on")
		jsonOK(w, map[string]string{"status": "ok"})
	}
}

// ── POST /api/cec/set-source ─────────────────────────────────────────────── //

// makeCECSetSourceHandler broadcasts ActiveSource to switch the AVR input.
func makeCECSetSourceHandler(c *cec.Client, log *slog.Logger) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if c == nil {
			jsonError(w, "CEC is not enabled (set cec.enabled = true in config)", http.StatusServiceUnavailable)
			return
		}
		if err := c.SetSource(); err != nil {
			log.Error("cec set-source failed", "err", err)
			jsonError(w, err.Error(), http.StatusInternalServerError)
			return
		}
		log.Info("cec set-source: ActiveSource broadcast sent")
		jsonOK(w, map[string]string{"status": "ok"})
	}
}

// ── POST /api/cec/standby ────────────────────────────────────────────────── //

// makeCECStandbyHandler sends the AVR to standby.
func makeCECStandbyHandler(c *cec.Client, log *slog.Logger) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if c == nil {
			jsonError(w, "CEC is not enabled (set cec.enabled = true in config)", http.StatusServiceUnavailable)
			return
		}
		if err := c.Standby(); err != nil {
			log.Error("cec standby failed", "err", err)
			jsonError(w, err.Error(), http.StatusInternalServerError)
			return
		}
		log.Info("cec standby: AVR sent to standby")
		jsonOK(w, map[string]string{"status": "ok"})
	}
}
