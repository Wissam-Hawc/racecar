#pragma once
// Freenove ESP32-WROVER CAM Board (FNK0060) camera pinout.

// Control pins (power-down, reset) — not wired on this board, so -1.
#define PWDN_GPIO_NUM     -1
#define RESET_GPIO_NUM    -1

// Master clock the ESP32 feeds TO the sensor so it runs.
#define XCLK_GPIO_NUM     21

// SCCB bus (I2C-style) used to configure the sensor: data + clock.
#define SIOD_GPIO_NUM     26
#define SIOC_GPIO_NUM     27

// 8-bit parallel pixel data bus (D0..D7) — one byte per clock.
#define Y9_GPIO_NUM       35
#define Y8_GPIO_NUM       34
#define Y7_GPIO_NUM       39
#define Y6_GPIO_NUM       36
#define Y5_GPIO_NUM       19
#define Y4_GPIO_NUM       18
#define Y3_GPIO_NUM        5
#define Y2_GPIO_NUM        4

// Timing / sync signals: frame sync, line valid, pixel clock.
#define VSYNC_GPIO_NUM    25
#define HREF_GPIO_NUM     23
#define PCLK_GPIO_NUM     22
