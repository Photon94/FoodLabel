#ifndef FOODLABEL_PRINTER_H
#define FOODLABEL_PRINTER_H
#include <stdint.h>
int foodlabel_usb(const uint8_t *payload, int length, int *transferred, char *message, int capacity);
int foodlabel_printers(void);
void *foodlabel_niim_open(char *message,int capacity);
void foodlabel_niim_close(void *opaque);
int foodlabel_niim_transfer(void *opaque,int writing,uint8_t *bytes,int length,int *transferred);
#endif
