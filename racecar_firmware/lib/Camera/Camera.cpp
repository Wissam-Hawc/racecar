  #include "Camera.h"

  #include <Arduino.h>

  #include "camera_pins.h"

  static esp_err_t streamHandler(httpd_req_t* req) {
    esp_err_t res =
        httpd_resp_set_type(req, "multipart/x-mixed-replace;boundary=frame");
    if (res != ESP_OK) return res;

    while (true) {
      camera_fb_t* fb = esp_camera_fb_get();
      if (!fb) {
        Serial.println("Camera capture failed");
        delay(50);
        continue; 
      }
      if (fb->format != PIXFORMAT_JPEG) {
        Serial.println("Non-JPEG frame, skipping");
        esp_camera_fb_return(fb);
        continue;
      }

      char partBuf[64];
      const size_t hlen = snprintf(partBuf, sizeof(partBuf),
          "--frame\r\nContent-Type: image/jpeg\r\nContent-Length: %u\r\n\r\n",
          fb->len);

      if (httpd_resp_send_chunk(req, partBuf, hlen) != ESP_OK ||
          httpd_resp_send_chunk(req, (const char*)fb->buf, fb->len) != ESP_OK ||
          httpd_resp_send_chunk(req, "\r\n", 2) != ESP_OK) {
        esp_camera_fb_return(fb);
        break;  // client disconnected
      }
      esp_camera_fb_return(fb);
    }
    return ESP_OK;
  }

  //initialize the camera
  bool Camera::begin() {

    camera_config_t config = {};
    config.ledc_channel = LEDC_CHANNEL_0;
    config.ledc_timer = LEDC_TIMER_0;

    config.pin_d0 = Y2_GPIO_NUM;
    config.pin_d1 = Y3_GPIO_NUM;
    config.pin_d2 = Y4_GPIO_NUM;
    config.pin_d3 = Y5_GPIO_NUM;
    config.pin_d4 = Y6_GPIO_NUM;
    config.pin_d5 = Y7_GPIO_NUM;
    config.pin_d6 = Y8_GPIO_NUM;
    config.pin_d7 = Y9_GPIO_NUM;

    config.pin_xclk = XCLK_GPIO_NUM;
    config.pin_pclk = PCLK_GPIO_NUM;
    config.pin_vsync = VSYNC_GPIO_NUM;
    config.pin_href = HREF_GPIO_NUM;
    config.pin_sscb_sda = SIOD_GPIO_NUM;
    config.pin_sscb_scl = SIOC_GPIO_NUM;
    config.pin_pwdn = PWDN_GPIO_NUM;
    config.pin_reset = RESET_GPIO_NUM;

    config.xclk_freq_hz = 20000000;  // 20 MHz -> faster readout, more fps
    config.pixel_format = PIXFORMAT_JPEG;

    if (psramFound()) {
      config.frame_size = FRAMESIZE_VGA;  // 640x480
      config.jpeg_quality = 14;           // higher number = smaller/faster
      config.fb_count = 2;
      config.fb_location = CAMERA_FB_IN_PSRAM;
      config.grab_mode = CAMERA_GRAB_LATEST;
    } else {
      config.frame_size = FRAMESIZE_QVGA;
      config.jpeg_quality = 15;
      config.fb_count = 1;
      config.fb_location = CAMERA_FB_IN_DRAM;
      config.grab_mode = CAMERA_GRAB_WHEN_EMPTY;
    }

    const esp_err_t err = esp_camera_init(&config);
    if (err != ESP_OK) {
      Serial.printf("Camera init failed: 0x%x\n", err);
      return false;
    }

    sensor_t* s = esp_camera_sensor_get();
    if (s) {
      s->set_brightness(s, 1);
      s->set_saturation(s, 0);
      s->set_vflip(s, 0);
      s->set_hmirror(s, 0);
    }

    Serial.printf("Camera initialized (PSRAM: %s)\n",
                  psramFound() ? "yes" : "no");
    return true;
  }

  bool Camera::startStream(uint16_t port) {
    if (_server != nullptr) return true;  // already running

    httpd_config_t config = HTTPD_DEFAULT_CONFIG();
    config.server_port = port;
    config.stack_size = 8192;
    config.task_priority = tskIDLE_PRIORITY + 5;

    if (httpd_start(&_server, &config) != ESP_OK) {
      _server = nullptr;
      Serial.println("Failed to start camera stream server");
      return false;
    }

    httpd_uri_t streamUri = {
        .uri = "/stream",
        .method = HTTP_GET,
        .handler = streamHandler,
    };
    httpd_register_uri_handler(_server, &streamUri);
    Serial.printf("Camera stream at http://<ip>:%u/stream\n", port);
    return true;
  }

  void Camera::stopStream() {
    if (_server != nullptr) {
      httpd_stop(_server);
      _server = nullptr;
      Serial.println("Camera stream stopped");
    }
  }
