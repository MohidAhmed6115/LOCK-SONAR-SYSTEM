# Loc Radar System — Ultrasonic Radar with Pin-2 Lock

> **Digital Logic Design · Riphah International University**  
> Instructor: Syed Hassaan  
> Authors: Hanan Shafay (72442) · Mohid Ahmed (73410) · Umair Hassan (74825)

A real-time ultrasonic radar system built with an Arduino Uno and visualised through a Processing 4 GUI. The radar sweeps an HC-SR04 sensor across a 180° arc, plots detected objects on a phosphor-green display, and features a hardware-toggled lock system that freezes the radar and shows a full animated LOCKED screen.

---

## Features

- **180° sweep** via servo motor in 2° steps
- **Distance measurement** up to 40 cm using HC-SR04 ultrasonic sensor
- **Hardware lock toggle** — falling edge on Pin 2 (INPUT_PULLUP) switches radar between `ACTIVE` and `LOCKED` states
- **Processing 4 display** at 1280×720 with:
  - Phosphor-green radar rings, spoke lines, and sweep trail
  - Red blip markers for detected objects
  - Sine-wave beep sounds (pitch varies with distance)
  - Animated LOCKED screen with CRT scanlines, pulsing rings, and padlock
  - Side panel with live angle, distance, FPS, and system info
  - Header with Riphah logo and author credits

---

## Hardware Required

| Component | Details |
|---|---|
| Arduino Uno | Microcontroller board |
| HC-SR04 | Ultrasonic distance sensor |
| Servo Motor | Any standard 5V hobby servo |
| Push button | Normally open, connected to Pin 2 and GND |
| Jumper wires | As needed |

### Wiring

| Signal | Arduino Pin |
|---|---|
| Servo | 12 |
| TRIG | 10 |
| ECHO | 11 |
| LOCK (button) | 2 → GND |

---

## Software Required

- [Arduino IDE](https://www.arduino.cc/en/software) with `Servo.h` (built-in)
- [Processing 4](https://processing.org/download) with libraries:
  - `processing.serial` (built-in)
  - `processing.sound` — install via Sketch → Import Library → Add Library → **Sound**

---

## Setup & Usage

1. Wire the components according to the table above.
2. Open `RadarLock/RadarLock.ino` in Arduino IDE, select your board and port, and upload.
3. Open `RadarProcessingBeep/RadarProcessingBeep.pde` in Processing 4.
4. Change the `COM_PORT` variable at the top of the sketch to match your Arduino's serial port (e.g. `"COM3"` on Windows, `"/dev/ttyUSB0"` on Linux).
5. Place `riphah.png` in the same folder as the `.pde` file.
6. Run the Processing sketch.
7. Press and release the button on Pin 2 to toggle the radar ON/OFF.

---

## Serial Protocol

| Message | Direction | Meaning |
|---|---|---|
| `angle,distance.` | Arduino → Processing | Sweep data (e.g. `90,15.`) |
| `ACTIVE.` | Arduino → Processing | Radar turned on |
| `LOCKED.` | Arduino → Processing | Radar turned off |

The Arduino sends `LOCKED.` every 500 ms while in locked state to keep the display in sync.

---

## Project Structure

```
Loc Radar System Riphah/
├── RadarLock/
│   └── RadarLock.ino          # Arduino firmware
└── RadarProcessingBeep/
    ├── RadarProcessingBeep.pde # Processing display sketch
    └── riphah.png              # University logo asset
```

---

## License

Academic project — Riphah International University, Department of Electrical & Computer Engineering. Not licensed for commercial use.
