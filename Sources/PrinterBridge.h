#ifndef FOODLABEL_PRINTER_H
#define FOODLABEL_PRINTER_H
#include <stdint.h>
int foodlabel_usb(const uint8_t *payload, int length, int *transferred, char *message, int capacity);
#endif
