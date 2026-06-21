#pragma once

#include "esp_camera.h"
#include "esp_http_server.h"

class Camera {
 public:
  bool begin();
  bool startStream(uint16_t port = 80);
  void stopStream();
  bool isStreaming() const { return _server != nullptr; }
 private:
  httpd_handle_t _server = nullptr;
};
