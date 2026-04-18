#ifndef MOCK_ARDUINO_H
#define MOCK_ARDUINO_H

#include <stdint.h>
#include <stdbool.h>
#include <math.h>

#define RAD_TO_DEG (180.0f / M_PI)
#define DEG_TO_RAD (M_PI / 180.0f)
#define PI M_PI
#define HEX 16

#define ARDUINO_INPUT 0
#define ARDUINO_OUTPUT 1
#define ARDUINO_INPUT_PULLUP 2
#define ARDUINO_INPUT_PULLDOWN 3
#define INPUT ARDUINO_INPUT
#define OUTPUT ARDUINO_OUTPUT
#define INPUT_PULLUP ARDUINO_INPUT_PULLUP
#define INPUT_PULLDOWN ARDUINO_INPUT_PULLDOWN
#define HIGH 1
#define LOW 0

#define AR_INTERNAL_3_0 0
#define AR_INTERNAL_2_4 1
#define AR_VDD 3

#define __DSB() do {} while(0)
#define __WFE() do {} while(0)

#define constrain(val, lo, hi) ((val) < (lo) ? (lo) : (val) > (hi) ? (hi) : (val))
#define F(x) x

static uint32_t _mock_millis = 0;
inline uint32_t millis() { return _mock_millis; }
inline void setMillis(uint32_t m) { _mock_millis = m; }

// Minimal Serial mock
class MockSerialClass {
public:
    void begin(long) {}
    void print(const char*) {}
    void print(float, int) {}
    void println(const char*) {}
    void println(float, int) {}
    void println() {}
    template<typename T> void print(T) {}
    template<typename T> void println(T) {}
    template<typename T> void print(T, int) {}
    int available() { return 0; }
    const char* readStringUntil(char) { return ""; }
    size_t write(const uint8_t*, size_t) { return 0; }
    void flush() {}
};

extern MockSerialClass Serial;

#endif // MOCK_ARDUINO_H
