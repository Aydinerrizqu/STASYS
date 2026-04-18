#include "config.h"
#include "data.h"
#include "globals.h"
#ifdef ARDUINO
#include <PDM.h>
#endif
#include <math.h>
// =============================================================================
// STSYS32 - PDM microphone and audio shot detection
// Migrated from dylemmas/STASYS_SEEEDXIAO (2026-04-16)
// =============================================================================


void pdmDataCallback();  // forward

// =============================================================================
// PDM MICROPHONE
// =============================================================================

void configurePDM() {
  PDM.onReceive(pdmDataCallback);
  PDM.setGain(20);
  if (!PDM.begin(PDM_CHANNELS, PDM_SAMPLE_RATE)) {
    Serial.println(F("[STSYS32-PDM] ERROR: begin() failed."));
  } else {
    Serial.println(F("[STSYS32-PDM] Microphone active: 16kHz mono"));
  }
}

void pdmDataCallback() {
  int available = PDM.available();
  if (available <= 0) return;

  int bytesRead   = PDM.read(pdmBuffer, min(available, (int)(PDM_BUFFER_SIZE * 2)));
  int samplesRead = bytesRead / 2;
  int16_t peak = 0;

  for (int i = 0; i < samplesRead; i++) {
    int16_t v = abs(pdmBuffer[i]);
    if (v > peak) peak = v;
  }

  if (peak > SHOT_AUDIO_THRESHOLD) {
    audioSpikeDetected = true;
    audioSpikeMs       = millis();
  }
}
