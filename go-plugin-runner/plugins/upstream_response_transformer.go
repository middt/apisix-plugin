package plugins

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/apache/apisix-go-plugin-runner/pkg/log"
	"github.com/apache/apisix-go-plugin-runner/pkg/plugin"
	pkgHTTP "github.com/apache/apisix-go-plugin-runner/pkg/http"
)

const PluginName = "upstream-response-transformer"

type UpstreamResponseTransformer struct {
	plugin.DefaultPlugin
	requestData sync.Map // Store request data temporarily
}

// Interface compliance check
var _ plugin.Plugin = &UpstreamResponseTransformer{}

type RequestData struct {
	URI             string            `json:"uri"`
	Method          string            `json:"method"`
	IP              string            `json:"ip"`
	Headers         map[string]string `json:"headers"`
	OriginalHeaders map[string]string `json:"original_headers"` // Store original upstream headers
}

type Config struct {
	ExternalAPIURL      string          `json:"external_api_url"`
	Timeout             int             `json:"timeout"`
	ForwardHeaders      []string        `json:"forward_headers"`
	Method              string          `json:"method"`
	Mode                string          `json:"mode"`
	ContentType         string          `json:"content_type"`
	ResponseHeaders     []ResponseHeader `json:"response_headers"`
}

type ResponseHeader struct {
	Name         string `json:"name"`
	Mode         string `json:"mode"`
	SuccessValue string `json:"success_value"`
	FailureValue string `json:"failure_value"`
}

type ExternalAPIPayload struct {
	UpstreamStatus  int               `json:"upstream_status"`
	UpstreamHeaders map[string]string `json:"upstream_headers"`
	UpstreamBody    string            `json:"upstream_body"`
	RequestURI      string            `json:"request_uri"`
	RequestMethod   string            `json:"request_method"`
	ClientIP        string            `json:"client_ip"`
	Timestamp       int64             `json:"timestamp"`
	Message         string            `json:"message"`
}

func (p *UpstreamResponseTransformer) Name() string {
	return PluginName
}

func (p *UpstreamResponseTransformer) ParseConf(in []byte) (interface{}, error) {
	config := Config{}
	err := json.Unmarshal(in, &config)
	if err != nil {
		log.Errorf("Failed to unmarshal configuration: %v", err)
		return nil, err
	}
	
	// Set defaults
	if config.Timeout == 0 {
		config.Timeout = 10000
	}
	if config.Method == "" {
		config.Method = "POST"
	}
	if config.Mode == "" {
		config.Mode = "notify"
	}
	if config.ContentType == "" {
		config.ContentType = "application/json"
	}
	
	log.Infof("Plugin %s configuration parsed successfully", PluginName)
	return config, nil
}

func (p *UpstreamResponseTransformer) RequestFilter(conf interface{}, w http.ResponseWriter, r pkgHTTP.Request) {
	config := conf.(Config)
	
	// Generate unique request ID for this request
	requestID := time.Now().UnixNano()
	
	// Extract request headers (focus on forward_headers)
	requestHeaders := make(map[string]string)
	
	// Debug: Log all available headers first
	log.Infof("RequestFilter: DEBUG - Checking %d forward_headers: %v", len(config.ForwardHeaders), config.ForwardHeaders)
	
	// Debug: Try to inspect what headers are actually available
	// Note: v0.5.0 API might have different header access methods
	log.Infof("RequestFilter: DEBUG - Request Method: %s", r.Method())
	
	// Try alternative header access if .Get() doesn't work
	header := r.Header()
	log.Infof("RequestFilter: DEBUG - Header object type: %T", header)
	
	// Get all headers from the request and store the ones we need
	for _, headerName := range config.ForwardHeaders {
		headerValue := r.Header().Get(headerName)
		log.Infof("RequestFilter: DEBUG - Checking header %s: value='%s'", headerName, headerValue)
		if headerValue != "" {
			requestHeaders[headerName] = headerValue
			log.Infof("RequestFilter: Captured header %s: %s", headerName, headerValue)
		} else {
			log.Warnf("RequestFilter: Header %s not found or empty", headerName)
		}
	}
	
	// Store request data for later use in ResponseFilter
	requestData := RequestData{
		URI:     getRequestURI(r),
		Method:  r.Method(),
		IP:      getClientIP(r),
		Headers: requestHeaders,
	}
	
	// Store with requestID
	p.requestData.Store(requestID, requestData)
	
	// Store requestID in response context (we'll retrieve it in ResponseFilter)
	// Note: This is a workaround since v0.5.0 context handling is complex
	// We'll use a time-based approach to match requests and responses
	
	log.Infof("RequestFilter: Stored request data for %s %s with %d forward headers", 
		requestData.Method, requestData.URI, len(requestHeaders))
}

func getClientIP(r pkgHTTP.Request) string {
	// Try different methods to get client IP
	if ip := r.Header().Get("X-Real-IP"); ip != "" {
		return ip
	}
	if ip := r.Header().Get("X-Forwarded-For"); ip != "" {
		return ip
	}
	// Fallback to a default value
	return "unknown"
}

func getRequestURI(r pkgHTTP.Request) string {
	// For now, use a simple fallback since v0.5.0 API doesn't have direct URL access
	// This will be populated correctly when the request info is used
	return "request-uri-from-filter"
}

func (p *UpstreamResponseTransformer) ResponseFilter(conf interface{}, w pkgHTTP.Response) {
	config := conf.(Config)

	log.Infof("ResponseFilter: Processing upstream response (mode: %s)", config.Mode)
	
	// Get the most recent request data (since we can't perfectly match request to response)
	var requestData RequestData
	var foundRequestData bool
	
	// Find the most recent request data (within last 5 seconds)
	cutoffTime := time.Now().UnixNano() - (5 * time.Second).Nanoseconds()
	
	p.requestData.Range(func(key, value interface{}) bool {
		if requestID, ok := key.(int64); ok && requestID > cutoffTime {
			requestData = value.(RequestData)
			foundRequestData = true
			// Clean up old data
			p.requestData.Delete(key)
			return false // Stop iteration
		}
		return true
	})
	
	if !foundRequestData {
		// Fallback to default values
		requestData = RequestData{
			URI:             "/unknown",
			Method:          "GET",
			IP:              "unknown",
			Headers:         make(map[string]string),
			OriginalHeaders: make(map[string]string),
		}
		log.Warnf("ResponseFilter: Could not find matching request data, using defaults")
	} else {
		log.Infof("ResponseFilter: Found request data with %d forward headers", len(requestData.Headers))
	}
	
	// For notify mode, do external API call without reading response body first
	if config.Mode == "notify" {
		// Prepare external API payload without upstream response body for notify mode
		payload := ExternalAPIPayload{
			UpstreamStatus:  w.StatusCode(),
			UpstreamHeaders: p.convertHeaders(w.Header()),
			UpstreamBody:    "", // Don't read body in notify mode
			RequestURI:      requestData.URI,
			RequestMethod:   requestData.Method,
			ClientIP:        requestData.IP,
			Timestamp:       time.Now().Unix(),
			Message:         "Upstream response data from APISIX Go Plugin (notify mode)",
		}
		
		// Call external API for notification purposes
		success, _, _ := p.callExternalAPI(config, payload, requestData.Headers)
		
		// Set response headers based on external API result
		p.setResponseHeaders(config, w, success)
		
		// In notify mode, we DON'T modify the response content-type or body
		// APISIX will handle the response naturally as it was from upstream
		log.Infof("Notify mode: External API notified (success: %v), letting APISIX handle response naturally", success)
		return
	}
	
	// For replace mode, read body and proceed with replacement logic
	body, err := w.ReadBody()
	if err != nil {
		log.Errorf("Failed to read upstream response body: %v", err)
		return
	}
	
	// Prepare external API payload with real request info
	payload := ExternalAPIPayload{
		UpstreamStatus:  w.StatusCode(),
		UpstreamHeaders: p.convertHeaders(w.Header()),
		UpstreamBody:    string(body),
		RequestURI:      requestData.URI,
		RequestMethod:   requestData.Method,
		ClientIP:        requestData.IP,
		Timestamp:       time.Now().Unix(),
		Message:         "Upstream response data from APISIX Go Plugin",
	}
	
	// Call external API with forward headers
	success, externalResponse, externalContentType := p.callExternalAPI(config, payload, requestData.Headers)
	
	// Set response headers based on external API result
	p.setResponseHeaders(config, w, success)
	
	// Handle response based on mode (replace mode only)
	if success && externalResponse != "" {
		// Replace mode: return external API response
		// Clear problematic headers first
		w.Header().Del("Content-Length")
		w.Header().Del("Transfer-Encoding")
		
		// Use external API's Content-Type (or fallback to config default)
		if externalContentType != "" {
			w.Header().Set("Content-Type", externalContentType)
			log.Infof("Response replaced with external API response (External Content-Type: %s)", externalContentType)
		} else {
			w.Header().Set("Content-Type", config.ContentType)
			log.Infof("Response replaced with external API response (Config Content-Type: %s)", config.ContentType)
		}
		
		// Write the external API response
		_, err := w.Write([]byte(externalResponse))
		if err != nil {
			log.Errorf("Failed to write external API response: %v", err)
		} else {
			log.Infof("Successfully wrote external API response (%d bytes)", len(externalResponse))
		}
	} else {
		// External API failed in replace mode: return original response with smart content-type detection
		// Clear problematic headers first  
		w.Header().Del("Content-Length")
		w.Header().Del("Transfer-Encoding")
		
		// Use smart content-type detection for original response
		smartContentType := p.detectContentType(body)
		w.Header().Set("Content-Type", smartContentType)
		log.Infof("Replace mode: External API failed, returning original response (Smart Content-Type: %s)", smartContentType)
		
		// Write the original response body
		_, err := w.Write(body)
		if err != nil {
			log.Errorf("Failed to write original response: %v", err)
		} else {
			log.Infof("Successfully wrote original response (%d bytes)", len(body))
		}
	}
}

func (p *UpstreamResponseTransformer) detectContentType(body []byte) string {
	// Trim whitespace to check actual content
	trimmed := bytes.TrimSpace(body)
	
	if len(trimmed) == 0 {
		return "text/plain; charset=utf-8"
	}
	
	// Check if it's JSON (starts with { or [)
	if (trimmed[0] == '{' && trimmed[len(trimmed)-1] == '}') ||
		(trimmed[0] == '[' && trimmed[len(trimmed)-1] == ']') {
		// Additional validation: try to parse as JSON
		var js interface{}
		if json.Unmarshal(trimmed, &js) == nil {
			return "application/json"
		}
	}
	
	// Check if it's XML (starts with <)
	if trimmed[0] == '<' {
		// Check for XML declaration or common XML tags
		lowerBody := strings.ToLower(string(trimmed))
		if strings.HasPrefix(lowerBody, "<?xml") || 
		   strings.Contains(lowerBody, "<soap:") ||
		   strings.Contains(lowerBody, "<rss") {
			return "application/xml; charset=utf-8"
		}
		// Check if it's HTML
		if strings.Contains(lowerBody, "<html") || 
		   strings.Contains(lowerBody, "<!doctype html") ||
		   strings.Contains(lowerBody, "<head>") ||
		   strings.Contains(lowerBody, "<body>") {
			return "text/html; charset=utf-8"
		}
		// Generic XML
		return "application/xml; charset=utf-8"
	}
	
	// Check for common text formats
	bodyStr := string(trimmed)
	if strings.HasPrefix(bodyStr, "data:") {
		return "text/plain; charset=utf-8"
	}
	
	// Check if it looks like a URL or query string
	if strings.Contains(bodyStr, "=") && strings.Contains(bodyStr, "&") {
		return "application/x-www-form-urlencoded"
	}
	
	// Default to plain text for everything else
	return "text/plain; charset=utf-8"
}

func (p *UpstreamResponseTransformer) convertHeaders(headers pkgHTTP.Header) map[string]string {
	result := make(map[string]string)
	
	// APISIX Go Plugin v0.5.0+ API için header iteration
	// Header interface'ini kullanarak header'ları iterate ediyoruz
	headerKeys := []string{
		"Content-Type", "Content-Length", "Content-Encoding",
		"Cache-Control", "ETag", "Last-Modified", "Expires", 
		"Access-Control-Allow-Origin", "Access-Control-Allow-Credentials",
		"Transfer-Encoding", "Vary", "Set-Cookie", "Server",
		"X-Powered-By", "X-Frame-Options", "X-Content-Type-Options",
	}
	
	// Bilinen header'ları kontrol et
	for _, key := range headerKeys {
		if value := headers.Get(key); value != "" {
			result[key] = value
		}
	}
	
	log.Infof("convertHeaders: Converted %d headers from upstream response", len(result))
	return result
}

func (p *UpstreamResponseTransformer) callExternalAPI(config Config, payload ExternalAPIPayload, forwardHeaders map[string]string) (bool, string, string) {
	// Prepare payload JSON
	payloadBytes, err := json.Marshal(payload)
	if err != nil {
		log.Errorf("Failed to marshal payload: %v", err)
		return false, "", ""
	}
	
	// Create HTTP client with timeout
	client := &http.Client{
		Timeout: time.Duration(config.Timeout) * time.Millisecond,
	}
	
	// Create request
	req, err := http.NewRequest(config.Method, config.ExternalAPIURL, bytes.NewBuffer(payloadBytes))
	if err != nil {
		log.Errorf("Failed to create external API request: %v", err)
		return false, "", ""
	}
	
	// Set default headers
	req.Header.Set("Content-Type", config.ContentType)
	req.Header.Set("User-Agent", "APISIX-Go-Plugin/1.0")
	
	// Add forward headers from original request
	for headerName, headerValue := range forwardHeaders {
		req.Header.Set(headerName, headerValue)
		log.Infof("External API: Added forward header %s: %s", headerName, headerValue)
	}
	
	log.Infof("External API: Making %s request to %s with Content-Type: %s and %d forward headers", 
		config.Method, config.ExternalAPIURL, config.ContentType, len(forwardHeaders))
	
	// Make the request
	ctx, cancel := context.WithTimeout(context.Background(), time.Duration(config.Timeout)*time.Millisecond)
	defer cancel()
	
	req = req.WithContext(ctx)
	resp, err := client.Do(req)
	if err != nil {
		log.Errorf("External API request failed: %v", err)
		return false, "", ""
	}
	defer resp.Body.Close()
	
	// Read response
	responseBody, err := io.ReadAll(resp.Body)
	if err != nil {
		log.Errorf("Failed to read external API response: %v", err)
		return false, "", ""
	}
	
	// Get external API response content-type
	externalContentType := resp.Header.Get("Content-Type")
	if externalContentType == "" {
		externalContentType = "application/json" // fallback for JSON APIs
	}
	
	success := resp.StatusCode >= 200 && resp.StatusCode < 300
	log.Infof("External API call completed: status=%d, success=%v, response-content-type=%s", resp.StatusCode, success, externalContentType)
	
	return success, string(responseBody), externalContentType
}

func (p *UpstreamResponseTransformer) setResponseHeaders(config Config, w pkgHTTP.Response, success bool) {
	for _, header := range config.ResponseHeaders {
		switch header.Mode {
		case "replace":
			if success {
				w.Header().Set(header.Name, header.SuccessValue)
			} else {
				w.Header().Set(header.Name, header.FailureValue)
			}
		case "notify":
			if success {
				w.Header().Set(header.Name, header.SuccessValue)
			}
		case "empty":
			if !success {
				w.Header().Set(header.Name, header.FailureValue)
			}
		}
	}
}

func init() {
	err := plugin.RegisterPlugin(&UpstreamResponseTransformer{})
	if err != nil {
		log.Errorf("Failed to register plugin %s: %v", PluginName, err)
	}
} 