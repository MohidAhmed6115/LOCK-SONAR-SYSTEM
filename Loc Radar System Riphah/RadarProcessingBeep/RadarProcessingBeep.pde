// ============================================================
//  RIPHAH INTERNATIONAL UNIVERSITY
//  Department of Electrical & Computer Engineering
//  ──────────────────────────────────────────────────────────
//  Subject  : Digital Logic Design
//  Project  : Ultrasonic Radar Display (Processing 4)
//  ──────────────────────────────────────────────────────────
//  Instructor   : Syed Hassaan
//  Lab Assistant: [Assistant]
//  ──────────────────────────────────────────────────────────
//  Authors:
//    Hanan Shafay  — SAP ID: 72442
//    Mohid Ahmed   — SAP ID: 73410
//    Umair Hassan  — SAP ID: 74825
//  ──────────────────────────────────────────────────────────
//  Change COM_PORT below to match your system (e.g. "COM3" or "/dev/ttyUSB0")
//
//  Serial protocol (Arduino → Processing):
//    "LOCKED."   → freeze radar, show LOCKED overlay
//    "ACTIVE."   → resume normal sweeping
//    "angle,distance."  → e.g. "90,15."
// ============================================================

import processing.serial.*;
import processing.sound.*;

// ── Serial ───────────────────────────────────────────────────
final String COM_PORT  = "COM3";    // ← CHANGE THIS
final int    BAUD_RATE = 9600;

Serial myPort;
String rawData   = "";
int    iAngle    = 0;
int    iDistance = 0;

// ── Layout ───────────────────────────────────────────────────
final int   MAX_DIST_CM = 40;
final float BOTTOM_PAD  = 0.10;   // status bar height fraction
final float TOP_PAD     = 0.13;   // header bar height fraction

// ── Trail / sweep ────────────────────────────────────────────
final int TRAIL_LEN = 90;
int[] trailAngle = new int[TRAIL_LEN];
int[] trailDist  = new int[TRAIL_LEN];
int   trailHead  = 0;

// ── Palette ──────────────────────────────────────────────────
color cGreen     = color(  0, 255,  70);
color cGreenDim  = color(  0,  80,  20);
color cGreenMid  = color(  0, 180,  50);
color cRed       = color(255,  40,  40);
color cAmber     = color(255, 180,   0);
color cBg        = color(  4,   8,   4);
color cPanel     = color(  8,  18,   8);
color cPanelBord = color(  0, 110,  40);
color cHeader    = color(  6,  14,   6);
color cAccent    = color(  0, 220,  80);
color cSubtle    = color(  0, 100,  35);

// ── Lock screen palette (from LockRadarSystem) ───────────────
// [ADDED] Colours used exclusively by the animated LOCKED overlay
color COL_LOCKED_BG = color(8,   4,   4);
color COL_LOCK_RED  = color(220, 30,  30);
color COL_LOCK_DIM  = color(80,  10,  10);
color COL_SCANLINE  = color(255, 60,  60, 18);

// ── Logo ─────────────────────────────────────────────────────
PImage logo;
// Original riphah.png ratio: 1077 × 322  →  aspect ≈ 3.343
final float LOGO_ASPECT = 1077.0 / 322.0;

// ── Fonts ────────────────────────────────────────────────────
PFont monoFont;
PFont monoSmall;
PFont titleFont;
PFont labelFont;

// ── Blip flash ───────────────────────────────────────────────
int blipFlash = 0;

// ── Beep sound ───────────────────────────────────────────────
SinOsc beepOsc;
Env    beepEnv;
int    lastBeepTime   = 0;
int    BEEP_COOLDOWN  = 150;

// ── Lock / Status state ──────────────────────────────────────
boolean radarActive  = true;   // false = show LOCKED overlay
boolean deniedFlash  = false;  // kept for potential future use
int     deniedTimer  = 0;
final int DENIED_DURATION = 2000;

// [ADDED] Lock-screen animation state (from LockRadarSystem)
float lockPulse  = 0;   // drives pulsing glow/colour on LOCKED screen
float lockWave   = 0;   // secondary wave for ring offsets
int   scanLineY  = 0;   // moving CRT scanline strip position

// ─────────────────────────────────────────────────────────────
void setup() {
  size(1280, 720);
  frameRate(60);
  smooth(4);
  colorMode(RGB, 255);

  monoFont  = createFont("Courier New Bold",    14, true);
  monoSmall = createFont("Courier New",         11, true);
  titleFont = createFont("Courier New Bold",    16, true);
  labelFont = createFont("Courier New",         12, true);

  logo = loadImage("riphah.png");

  // ── Sound setup ──
  beepOsc = new SinOsc(this);
  beepEnv = new Env(this);

  for (int i = 0; i < TRAIL_LEN; i++) {
    trailAngle[i] = 0;
    trailDist[i]  = MAX_DIST_CM + 1;
  }

  try {
    myPort = new Serial(this, COM_PORT, BAUD_RATE);
    myPort.bufferUntil('.');
  } catch (Exception e) {
    println("⚠  Could not open " + COM_PORT + " — running in demo mode.");
  }
}

// ─────────────────────────────────────────────────────────────
void draw() {
  // ── LOCKED mode: full replacement screen (from LockRadarSystem) ──
  // [MODIFIED] When locked, delegate entirely to the animated locked screen
  //            instead of drawing a semi-transparent veil over the radar.
  if (!radarActive) {
    drawLockedScreen();
    return;   // skip all normal radar drawing
  }

  // ── ACTIVE mode: normal radar UI ─────────────────────────
  background(cBg);

  drawScanlines();
  drawHeader();
  drawRadarBackground();
  drawSweepTrail();
  drawObjects();
  drawSweepLine();
  drawRadarRings();
  drawRadarLabels();
  drawStatusBar();
  drawSidePanel();

  // DENIED banner (auto-expires)
  if (deniedFlash) {
    drawDeniedOverlay();
    if (millis() - deniedTimer > DENIED_DURATION) {
      deniedFlash = false;
    }
  }

  if (blipFlash > 0) blipFlash--;
}

// ─────────────────────────────────────────────────────────────
//  SERIAL EVENT
//  [MODIFIED] Robustness improvements from LockRadarSystem:
//    • Null-guard at top
//    • Strip trailing '.' if present after trim
//    • Per-part trim before int() conversion
//    • try/catch around int parsing prevents crashes on garbage data
//    • Accepts bare "LOCKED" / "ACTIVE" tokens (no "STATUS:" prefix)
//      while also tolerating the old "STATUS:LOCKED" / "STATUS:ACTIVE"
//      format for backwards compatibility
// ─────────────────────────────────────────────────────────────
void serialEvent(Serial p) {
  String val = p.readStringUntil('.');
  if (val == null) return;                       // [ADDED] null-guard

  val = trim(val);
  if (val.endsWith(".")) val = val.substring(0, val.length() - 1); // [ADDED] strip trailing dot

  // ── Status tokens ──────────────────────────────────────
  if (val.equals("LOCKED") || val.equals("STATUS:LOCKED")) {
    radarActive = false;

  } else if (val.equals("ACTIVE") || val.equals("STATUS:ACTIVE")) {
    radarActive = true;
    deniedFlash = false;

  } else if (val.equals("STATUS:DENIED")) {
    deniedFlash = true;
    deniedTimer = millis();

  } else {
    // ── Angle,distance data: "angle,distance" ──────────
    String[] parts = split(val, ',');
    if (parts.length == 2) {
      try {                                      // [ADDED] crash-safe int parsing
        int ang  = int(trim(parts[0]));
        int dist = int(trim(parts[1]));

        iAngle    = ang;
        iDistance = dist;

        trailAngle[trailHead] = ang;
        trailDist[trailHead]  = dist;
        trailHead = (trailHead + 1) % TRAIL_LEN;

        if (dist <= MAX_DIST_CM) {
          blipFlash = 6;
          int now = millis();
          if (now - lastBeepTime > BEEP_COOLDOWN) {
            lastBeepTime = now;
            float freq = map(dist, 0, MAX_DIST_CM, 1800, 900);
            beepOsc.freq(freq);
            beepOsc.play();
            beepEnv.play(beepOsc, 0.001, 0.05, 0.9, 0.05);
          }
        }
      } catch (Exception e) {
        // Silently discard malformed packet
      }
    }
  }
}

// ─────────────────────────────────────────────────────────────
//  LOCKED SCREEN  (full replacement — adapted from LockRadarSystem)
//  [ADDED] Replaces the old semi-transparent veil overlay.
//  Draws a dedicated full-screen locked state with:
//    • CRT scanline effect + moving scan strip
//    • Animated padlock primitive
//    • Pulsing concentric rings
//    • Military-style corner brackets
//    • Status bar matching the RadarProcessing colour scheme
// ─────────────────────────────────────────────────────────────
void drawLockedScreen() {
  background(COL_LOCKED_BG);

  // Advance animation counters
  lockPulse = (lockPulse + 0.04) % TWO_PI;
  lockWave  = (lockWave  + 0.02) % TWO_PI;
  float pulse = 0.5 + 0.5 * sin(lockPulse);

  // ── CRT scanlines ────────────────────────────────────────
  drawLockedScanlines();

  // ── Radial glow behind padlock ────────────────────────────
  float lx    = width  / 2.0;
  float ly    = height / 2.0 - 30;
  float glowR = 160 + 20 * pulse;
  for (int i = 10; i >= 1; i--) {
    float a = map(i, 10, 1, 0, 60 * pulse);
    fill(lerpColor(COL_LOCK_DIM, COL_LOCK_RED, pulse), a);
    noStroke();
    ellipse(lx, ly, glowR * i / 5.0, glowR * i / 5.0);
  }

  // ── Padlock primitive ─────────────────────────────────────
  color bodyCol = lerpColor(COL_LOCK_DIM, COL_LOCK_RED, pulse);

  // Shackle arc
  stroke(bodyCol);
  strokeWeight(10);
  noFill();
  arc(lx, ly - 28, 74, 74, PI + HALF_PI * 0.6, TWO_PI + HALF_PI * 0.4);
  noStroke();

  // Body
  fill(bodyCol);
  rectMode(CENTER);
  rect(lx, ly + 28, 94, 72, 10);

  // Keyhole circle
  fill(COL_LOCKED_BG);
  ellipse(lx, ly + 22, 22, 22);

  // Keyhole slot
  fill(COL_LOCKED_BG);
  rect(lx, ly + 40, 10, 24, 4);

  rectMode(CORNER);

  // ── "SYSTEM LOCKED" text ──────────────────────────────────
  textFont(titleFont);
  textSize(44);
  textAlign(CENTER, CENTER);
  color textCol = lerpColor(color(100, 10, 10), COL_LOCK_RED, pulse);
  fill(textCol);
  text("SYSTEM LOCKED", lx, height / 2.0 + 90);

  // Blinking sub-text
  if (frameCount % 60 < 40) {
    textSize(15);
    fill(COL_LOCK_RED, 160);
    text("RADAR OFFLINE — AWAITING AUTHORISATION", lx, height / 2.0 + 135);
  }

  // ── Pulsing rings around padlock ──────────────────────────
  noFill();
  for (int i = 3; i >= 1; i--) {
    float ringR = 90 + i * 18 + 12 * sin(lockPulse + i);
    stroke(COL_LOCK_RED, 40 * pulse / i);
    strokeWeight(2);
    ellipse(lx, ly, ringR * 2, ringR * 2);
  }
  noStroke();

  // ── Top status bar ────────────────────────────────────────
  textFont(monoFont);
  textSize(13);
  textAlign(CENTER, CENTER);
  fill(COL_LOCK_RED, 180);
  text("RADAR STATUS: OFFLINE  |  SYSTEM LOCKED  |  PORT: " + COM_PORT, lx, 30);

  // ── Corner brackets (military UI) ────────────────────────
  drawCornerBrackets();
}

// [ADDED] CRT scanlines used only during the LOCKED screen
void drawLockedScanlines() {
  scanLineY = (scanLineY + 2) % height;
  for (int y = 0; y < height; y += 4) {
    fill(COL_SCANLINE);
    noStroke();
    rect(0, y, width, 2);
  }
  // Moving bright red strip
  fill(255, 30, 30, 25);
  rect(0, scanLineY, width, 60);
}

// [ADDED] Corner brackets drawn during the LOCKED screen
void drawCornerBrackets() {
  int m = 20, len = 30;
  stroke(COL_LOCK_RED, 120);
  strokeWeight(2);
  // Top-left
  line(m,         m,          m + len,    m);
  line(m,         m,          m,          m + len);
  // Top-right
  line(width - m, m,          width-m-len, m);
  line(width - m, m,          width - m,  m + len);
  // Bottom-left
  line(m,         height - m, m + len,    height - m);
  line(m,         height - m, m,          height - m - len);
  // Bottom-right
  line(width - m, height - m, width-m-len, height - m);
  line(width - m, height - m, width - m,  height - m - len);
  noStroke();
}

// ─────────────────────────────────────────────────────────────
//  OVERLAY: DENIED
//  Full-width banner that flashes red for DENIED_DURATION ms
// ─────────────────────────────────────────────────────────────
void drawDeniedOverlay() {
  float elapsed  = millis() - deniedTimer;
  float progress = constrain(elapsed / DENIED_DURATION, 0, 1);
  float alpha;
  if (progress < 0.15) {
    alpha = map(progress, 0, 0.15, 0, 255);
  } else if (progress < 0.75) {
    alpha = 255;
  } else {
    alpha = map(progress, 0.75, 1.0, 255, 0);
  }

  noStroke();
  fill(120, 0, 0, (int)(alpha * 0.55));
  rect(0, 0, width, height);

  stroke(255, 30, 30, (int) alpha);
  strokeWeight(5);
  noFill();
  rect(4, 4, width - 8, height - 8, 4);

  float midX = width  / 2.0;
  float midY = height / 2.0;

  textFont(titleFont);
  textSize(56);
  textAlign(CENTER, CENTER);
  noStroke();
  fill(255, 30, 30, (int) alpha);
  text("ACCESS DENIED", midX, midY - 24);

  textFont(monoSmall);
  textSize(15);
  fill(255, 100, 100, (int)(alpha * 0.85));
  text("INCORRECT PASSWORD — RADAR REMAINS OFFLINE", midX, midY + 28);
}

// ─────────────────────────────────────────────────────────────
//  HEADER BAR — top strip with logo, title & project info
// ─────────────────────────────────────────────────────────────
void drawHeader() {
  float hH = height * TOP_PAD;

  noStroke();
  fill(cHeader);
  rect(0, 0, width, hH);

  stroke(cPanelBord);
  strokeWeight(2);
  line(0, hH - 2, width, hH - 2);
  stroke(0, 60, 20);
  strokeWeight(1);
  line(0, hH, width, hH);

  // ── Logo (left) ──
  float logoH  = hH * 0.55;
  float logoW  = logoH * LOGO_ASPECT;
  float logoX  = 18;
  float logoY  = (hH - logoH) / 2;

  if (logo != null && logo.width > 0) {
    float padX = 8, padY = 6;
    noStroke();
    fill(245, 245, 242);
    rect(logoX - padX, logoY - padY, logoW + padX * 2, logoH + padY * 2, 5);
    stroke(180, 180, 175);
    strokeWeight(1);
    noFill();
    rect(logoX - padX, logoY - padY, logoW + padX * 2, logoH + padY * 2, 5);
    image(logo, logoX, logoY, logoW, logoH);
  } else {
    noStroke();
    fill(cPanel);
    rect(logoX, logoY, logoW, logoH, 4);
    stroke(cPanelBord);
    strokeWeight(1);
    noFill();
    rect(logoX, logoY, logoW, logoH, 4);
    textFont(monoFont);
    textSize(11);
    textAlign(CENTER, CENTER);
    fill(cAccent);
    text("RIPHAH INTERNATIONAL UNIVERSITY", logoX + logoW/2, logoY + logoH/2);
  }

  // ── Vertical divider ──
  float divX = logoX + logoW + 18;
  stroke(cSubtle);
  strokeWeight(1);
  line(divX, hH * 0.18, divX, hH * 0.82);

  // ── University & subject title ──
  float tx  = divX + 18;
  float midY = hH / 2;

  textFont(titleFont);
  textSize(15);
  textAlign(LEFT, CENTER);
  fill(cAccent);
  text("RIPHAH INTERNATIONAL UNIVERSITY", tx, midY - 14);

  textFont(labelFont);
  textSize(12);
  fill(cGreenMid);
  text("Digital Logic Design  ·  Ultrasonic Radar Display Project", tx, midY + 6);

  textFont(monoSmall);
  textSize(10);
  fill(cSubtle);
  text("Instructor: Syed Hassaan     Lab Assistant: [Assistant]", tx, midY + 22);

  // ── Right info block ──
  float rx = width - 16;
  textAlign(RIGHT, CENTER);

  textFont(monoSmall);
  textSize(10);
  fill(cSubtle);
  text("AUTHORS", rx, midY - 22);

  textFont(monoFont);
  textSize(11);
  fill(cGreenMid);
  text("Hanan Shafay  (SAP: 72442)", rx, midY - 8);
  text("Mohid Ahmed   (SAP: 73410)", rx, midY + 6);
  text("Umair Hassan  (SAP: 74825)", rx, midY + 20);
}

// ─────────────────────────────────────────────────────────────
//  RADAR BACKGROUND
// ─────────────────────────────────────────────────────────────
void drawRadarBackground() {
  pushMatrix();
  translate(cx(), cy());
  noStroke();
  fill(0, 16, 4);
  arc(0, 0, radarD(), radarD(), PI, TWO_PI);

  for (int i = 0; i < 8; i++) {
    float frac = 1.0 - (float)i / 8.0;
    fill(0, (int)(8 * frac), 0, 18);
    arc(0, 0, radarD() * frac, radarD() * frac, PI, TWO_PI);
  }
  popMatrix();
}

// ─────────────────────────────────────────────────────────────
//  RINGS & SPOKES
// ─────────────────────────────────────────────────────────────
void drawRadarRings() {
  pushMatrix();
  translate(cx(), cy());
  noFill();

  int[] cmMarks = { 10, 20, 30, 40 };
  for (int i = 0; i < cmMarks.length; i++) {
    float frac   = (float) cmMarks[i] / MAX_DIST_CM;
    float dia    = radarD() * frac;
    float bright = map(i, 0, cmMarks.length - 1, 55, 155);
    stroke(0, (int) bright, 0);
    strokeWeight(i == cmMarks.length - 1 ? 2 : 1);
    arc(0, 0, dia, dia, PI, TWO_PI);
  }

  stroke(0, 90, 0);
  strokeWeight(1);
  float r = radarD() / 2;
  for (int deg = 0; deg <= 180; deg += 30) {
    float rad = radians(deg);
    line(0, 0, -r * cos(rad), -r * sin(rad));
  }

  stroke(0, 130, 0);
  strokeWeight(2);
  line(-r, 0, r, 0);

  noStroke();
  fill(0, 220, 60, 180);
  ellipse(0, 0, 6, 6);

  popMatrix();
}

// ─────────────────────────────────────────────────────────────
//  SWEEP TRAIL
// ─────────────────────────────────────────────────────────────
void drawSweepTrail() {
  pushMatrix();
  translate(cx(), cy());
  float r = radarD() / 2;

  for (int i = 0; i < TRAIL_LEN; i++) {
    int   idx   = (trailHead - 1 - i + TRAIL_LEN) % TRAIL_LEN;
    float age   = (float)(i + 1) / TRAIL_LEN;
    float alpha = (1.0 - age) * 130;
    float ang   = radians(trailAngle[idx]);

    stroke(0, (int)(75 * (1 - age)), 0, (int) alpha);
    strokeWeight(lerp(4.5, 1, age));
    line(0, 0, -r * cos(ang), -r * sin(ang));
  }
  popMatrix();
}

// ─────────────────────────────────────────────────────────────
//  SWEEP LINE
// ─────────────────────────────────────────────────────────────
void drawSweepLine() {
  pushMatrix();
  translate(cx(), cy());
  float r   = radarD() / 2;
  float ang = radians(iAngle);

  for (int g = 5; g >= 0; g--) {
    int alpha = (int) map(g, 5, 0, 15, 210);
    stroke(70, 255, 90, alpha);
    strokeWeight(g * 2 + 1);
    line(0, 0, -r * cos(ang), -r * sin(ang));
  }
  popMatrix();
}

// ─────────────────────────────────────────────────────────────
//  DETECTED OBJECTS
// ─────────────────────────────────────────────────────────────
void drawObjects() {
  pushMatrix();
  translate(cx(), cy());
  float r = radarD() / 2;

  for (int i = 0; i < TRAIL_LEN; i++) {
    if (trailDist[i] > MAX_DIST_CM) continue;

    float age   = (float)((trailHead - 1 - i + TRAIL_LEN) % TRAIL_LEN) / TRAIL_LEN;
    float alpha = (1.0 - age) * 255;
    float frac  = (float) trailDist[i] / MAX_DIST_CM;
    float dist  = r * frac;
    float ang   = radians(trailAngle[i]);

    float x = -dist * cos(ang);
    float y = -dist * sin(ang);

    noStroke();
    fill(255, 30, 30, (int)(alpha * 0.25));
    ellipse(x, y, 26, 26);
    fill(255, 55, 55, (int)(alpha * 0.55));
    ellipse(x, y, 14, 14);
    fill(255, 110, 110, (int) alpha);
    ellipse(x, y,  7,  7);
  }
  popMatrix();
}

// ─────────────────────────────────────────────────────────────
//  RADAR LABELS
// ─────────────────────────────────────────────────────────────
void drawRadarLabels() {
  pushMatrix();
  translate(cx(), cy());
  textFont(labelFont);
  textSize(12);
  float r = radarD() / 2;

  fill(0, 200, 55);
  noStroke();
  int[] degs = { 30, 60, 90, 120, 150 };
  for (int d : degs) {
    float ang = radians(d);
    float lx  = -(r + 20) * cos(ang);
    float ly  = -(r + 20) * sin(ang);
    textAlign(CENTER, CENTER);
    text(d + "°", lx, ly);
  }
  textAlign(CENTER, CENTER);
  text("0°",   r + 20, 7);
  text("180°", -r - 26, 7);

  int[] cms = { 10, 20, 30, 40 };
  textAlign(LEFT, CENTER);
  for (int cm : cms) {
    text(cm + " cm", r * ((float) cm / MAX_DIST_CM) + 5, -7);
  }
  popMatrix();
}

// ─────────────────────────────────────────────────────────────
//  STATUS BAR  — bottom strip
// ─────────────────────────────────────────────────────────────
void drawStatusBar() {
  float bY = height - height * BOTTOM_PAD;
  float bH = height * BOTTOM_PAD;

  noStroke();
  fill(cHeader);
  rect(0, bY, width, bH);

  stroke(cPanelBord);
  strokeWeight(2);
  line(0, bY + 1, width, bY + 1);
  stroke(0, 60, 20);
  strokeWeight(1);
  line(0, bY, width, bY);

  float midY = bY + bH / 2;

  stroke(cSubtle);
  strokeWeight(1);
  line(width * 0.38f, bY + bH * 0.2f, width * 0.38f, bY + bH * 0.8f);
  line(width * 0.56f, bY + bH * 0.2f, width * 0.56f, bY + bH * 0.8f);
  line(width * 0.74f, bY + bH * 0.2f, width * 0.74f, bY + bH * 0.8f);

  textFont(monoFont);
  textSize(13);

  textAlign(LEFT, CENTER);
  fill(cSubtle);
  textFont(monoSmall);
  textSize(10);
  text("RIPHAH INTERNATIONAL UNIVERSITY — DIGITAL LOGIC DESIGN", 16, midY - 9);
  fill(cGreenMid);
  textFont(monoFont);
  textSize(12);
  text("Hanan Shafay · Mohid Ahmed · Umair Hassan", 16, midY + 8);

  textAlign(CENTER, CENTER);
  fill(cSubtle);
  textFont(monoSmall);
  textSize(10);
  text("SWEEP ANGLE", width * 0.47f, midY - 9);
  fill(cAccent);
  textFont(monoFont);
  textSize(15);
  text(nf(iAngle, 3) + "°", width * 0.47f, midY + 8);

  boolean inRange = (iDistance <= MAX_DIST_CM);
  textAlign(CENTER, CENTER);
  fill(cSubtle);
  textFont(monoSmall);
  textSize(10);
  text("DISTANCE", width * 0.65f, midY - 9);
  fill(inRange ? cRed : cAmber);
  textFont(monoFont);
  textSize(15);
  text(inRange ? nf(iDistance, 2) + " cm" : "--- cm", width * 0.65f, midY + 8);

  textAlign(CENTER, CENTER);
  fill(cSubtle);
  textFont(monoSmall);
  textSize(10);
  text("STATUS", width * 0.87f, midY - 9);

  // [MODIFIED] Status badge now uses plain "LOCKED" / "SCANNING" language
  //            consistent with the new serial protocol
  if (deniedFlash) {
    fill(blipFlash > 0 ? cRed : color(200, 20, 20));
    textFont(monoFont);
    textSize(13);
    text("✕  ACCESS DENIED", width * 0.87f, midY + 8);
  } else if (inRange) {
    fill(blipFlash > 0 ? cRed : color(180, 0, 0));
    textFont(monoFont);
    textSize(13);
    text("⬤  OBJECT DETECTED", width * 0.87f, midY + 8);
  } else {
    fill(cGreenDim);
    textFont(monoFont);
    textSize(13);
    text("◯  SCANNING...", width * 0.87f, midY + 8);
  }
}

// ─────────────────────────────────────────────────────────────
//  SIDE PANEL  — right info panel
// ─────────────────────────────────────────────────────────────
void drawSidePanel() {
  float pX = width  * 0.795f;
  float pY = height * TOP_PAD + 10;
  float pW = width  * 0.195f;
  float pH = height * (1.0 - TOP_PAD - BOTTOM_PAD) - 20;

  noStroke();
  fill(cHeader);
  rect(pX, pY, pW, pH, 6);

  stroke(cPanelBord);
  strokeWeight(1);
  noFill();
  rect(pX, pY, pW, pH, 6);

  stroke(cAccent);
  strokeWeight(2);
  line(pX + 10, pY + 2, pX + pW - 10, pY + 2);

  float tx = pX + 14;
  float ty = pY + 16;
  float lh = 22;

  textFont(titleFont);
  textSize(12);
  textAlign(LEFT, TOP);
  fill(cAccent);
  text("SYSTEM STATUS", tx, ty);
  ty += lh;

  stroke(cSubtle);
  strokeWeight(1);
  line(tx, ty, pX + pW - 14, ty);
  ty += lh * 0.6;

  textFont(monoSmall);
  textSize(11);

  String[][] rows = {
    {"MODE",    "SWEEP"},
    {"RANGE",   "0 – 40 cm"},
    {"STEP",    "2°"},
    {"SENSOR",  "HC-SR04"},
    {"BOARD",   "Arduino Uno"},
  };
  for (String[] row : rows) {
    fill(cSubtle);
    text(row[0], tx, ty);
    fill(cGreenMid);
    text(row[1], tx + 62, ty);
    ty += lh;
  }

  ty += lh * 0.3;
  stroke(cSubtle);
  line(tx, ty, pX + pW - 14, ty);
  ty += lh * 0.6;

  String[][] rows2 = {
    {"PORT",  COM_PORT},
    {"BAUD",  str(BAUD_RATE)},
    {"FPS",   nf(frameRate, 2, 1)},
  };
  for (String[] row : rows2) {
    fill(cSubtle);
    text(row[0], tx, ty);
    fill(cGreenMid);
    text(row[1], tx + 62, ty);
    ty += lh;
  }

  ty += lh * 0.3;
  stroke(cSubtle);
  line(tx, ty, pX + pW - 14, ty);
  ty += lh * 0.6;

  fill(cAccent);
  textFont(monoSmall);
  textSize(11);
  text("SWEEP POSITION", tx, ty);
  ty += lh * 0.85;

  float barW   = pW - 28;
  float filled = map(iAngle, 0, 180, 0, barW);

  stroke(cSubtle);
  strokeWeight(1);
  noFill();
  rect(tx, ty, barW, 9, 4);

  noStroke();
  fill(color(0, 180, 55));
  if (filled > 0) rect(tx, ty, filled, 9, 4);

  ty += lh * 0.85;
  textAlign(LEFT, TOP);
  fill(cSubtle);
  textFont(monoSmall);
  textSize(10);
  text("0°", tx, ty);
  textAlign(RIGHT, TOP);
  text("180°", pX + pW - 14, ty);

  ty += lh * 1.1;
  stroke(cSubtle);
  line(tx, ty, pX + pW - 14, ty);
  ty += lh * 0.6;

  textFont(monoSmall);
  textSize(10);
  textAlign(LEFT, TOP);
  fill(cAccent);
  text("PROJECT INFO", tx, ty);           ty += lh * 0.9;
  fill(cSubtle);
  text("Subject:", tx, ty);
  fill(cGreenMid);
  text("Dig. Logic Design", tx + 58, ty); ty += lh;
  fill(cSubtle);
  text("Instr.:", tx, ty);
  fill(cGreenMid);
  text("Syed Hassaan", tx + 58, ty);      ty += lh;
  fill(cSubtle);
  text("Lab Asst:", tx, ty);
  fill(cGreenMid);
  text("[Assistant]", tx + 58, ty);       ty += lh * 1.1;

  stroke(cSubtle);
  line(tx, ty, pX + pW - 14, ty);
  ty += lh * 0.6;

  fill(cAccent);
  text("AUTHORS", tx, ty);                ty += lh * 0.9;
  String[][] authors = {
    { "Hanan Shafay",  "72442" },
    { "Mohid Ahmed",   "73410" },
    { "Umair Hassan",  "74825" },
  };
  for (String[] a : authors) {
    fill(cGreenMid);
    text(a[0], tx, ty);
    fill(cSubtle);
    textAlign(RIGHT, TOP);
    text("SAP: " + a[1], pX + pW - 14, ty);
    textAlign(LEFT, TOP);
    ty += lh;
  }
}

// ─────────────────────────────────────────────────────────────
//  SCANLINES  (active radar mode — subtle static lines)
// ─────────────────────────────────────────────────────────────
void drawScanlines() {
  stroke(0, 0, 0, 22);
  strokeWeight(1);
  for (int y = 0; y < height; y += 3) {
    line(0, y, width, y);
  }
}

// ─────────────────────────────────────────────────────────────
//  HELPERS
// ─────────────────────────────────────────────────────────────
float cx()     { return width * 0.485; }
float cy()     { return height * (1.0 - BOTTOM_PAD) - 8; }
float radarD() {
  float usableH = height * (1.0 - TOP_PAD - BOTTOM_PAD) - 20;
  float usableW = width  * 0.77;
  return min(usableW, usableH * 1.82);
}
