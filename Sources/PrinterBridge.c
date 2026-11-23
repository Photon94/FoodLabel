#include "PrinterBridge.h"
#include <libusb.h>
#include <stdio.h>
#include <string.h>

int foodlabel_usb(const uint8_t *payload, int length, int *transferred, char *message, int capacity) {
    *transferred = 0;
    if (length < 0 || length > 2000000 || (length > 0 && !payload)) {
        snprintf(message,capacity,"Недопустимый размер задания."); return -1;
    }
    libusb_context *ctx = NULL; libusb_device_handle *h = NULL;
    struct libusb_config_descriptor *config = NULL; libusb_device **list = NULL;
    int iface = -1, output = -1, input = -1, claimed = 0, result = -1;
    int rc = libusb_init(&ctx);
    if (rc < 0) { snprintf(message,capacity,"USB: %s",libusb_error_name(rc)); return rc; }
    ssize_t count = libusb_get_device_list(ctx,&list);
    if (count < 0) { snprintf(message,capacity,"Не удалось прочитать список USB-устройств."); goto cleanup; }
    libusb_device *target = NULL; int matches = 0;
    for (ssize_t i=0;i<count;i++) {
        struct libusb_device_descriptor d;
        if (libusb_get_device_descriptor(list[i],&d)==0 && d.idVendor==0x1fc9 && d.idProduct==0x2016) { target=list[i]; matches++; }
    }
    if (matches!=1) { snprintf(message,capacity,matches==0 ? "Принтер не найден. Подключите Xprinter по USB и включите питание." : "Найдено несколько принтеров. Оставьте подключённым только нужный Xprinter."); goto cleanup; }
    rc=libusb_open(target,&h);
    if (rc<0) { snprintf(message,capacity,"Нет доступа к принтеру. Закройте другие программы печати. USB: %s",libusb_error_name(rc)); goto cleanup; }
    rc=libusb_get_active_config_descriptor(target,&config);
    if (rc<0) { snprintf(message,capacity,"Не удалось прочитать параметры USB."); goto cleanup; }
    for (int i=0;i<config->bNumInterfaces;i++) {
        for (int j=0;j<config->interface[i].num_altsetting;j++) {
            const struct libusb_interface_descriptor *d=&config->interface[i].altsetting[j];
            if (d->bInterfaceClass!=7 || d->bAlternateSetting!=0) continue;
            int found_out=-1,found_in=-1;
            for (int k=0;k<d->bNumEndpoints;k++) {
                const struct libusb_endpoint_descriptor *e=&d->endpoint[k];
                if ((e->bmAttributes&3)!=LIBUSB_TRANSFER_TYPE_BULK) continue;
                if (e->bEndpointAddress&LIBUSB_ENDPOINT_IN) found_in=e->bEndpointAddress; else found_out=e->bEndpointAddress;
            }
            if (found_out>=0) { iface=d->bInterfaceNumber; output=found_out; input=found_in; }
        }
    }
    if (iface<0) { snprintf(message,capacity,"Не найден интерфейс печати USB."); goto cleanup; }
    rc=libusb_claim_interface(h,iface);
    if (rc<0) { snprintf(message,capacity,"Принтер занят или недоступен. Закройте другие программы печати. USB: %s",libusb_error_name(rc)); goto cleanup; }
    claimed=1;
    unsigned char id[1024]={0};
    int n=libusb_control_transfer(h,0xa1,0,0,iface,id,sizeof(id)-1,2000);
    if (n<=2 || !strstr((char *)id+2,"XP-365B") || !strstr((char *)id+2,"TSPL")) {
        snprintf(message,capacity,"Подключённое устройство не подтвердило модель XP-365B и язык TSPL."); goto cleanup;
    }
    if (length==0) { snprintf(message,capacity,"Xprinter XP-365B подключён по USB."); result=0; goto cleanup; }
    if (input<0) { snprintf(message,capacity,"Не удалось найти канал статуса принтера."); goto cleanup; }
    unsigned char request[]={0x1b,0x21,0x3f}; int nbytes=0;
    rc=libusb_bulk_transfer(h,output,request,sizeof(request),&nbytes,2000);
    if (rc<0 || nbytes!=sizeof(request)) { snprintf(message,capacity,"Принтер не ответил на проверку готовности. Задание не отправлено."); goto cleanup; }
    unsigned char status[64]={0};
    rc=libusb_bulk_transfer(h,input,status,sizeof(status),&nbytes,3000);
    if (rc<0 || nbytes!=1) { snprintf(message,capacity,"Не удалось определить состояние принтера. Задание не отправлено."); goto cleanup; }
    if (status[0]!=0) {
        const char *reason=(status[0]&1)?"Закройте крышку принтера.":(status[0]&4)?"Проверьте бумагу в принтере.":(status[0]&2)?"Проверьте, не застряла ли бумага.":(status[0]&0x10)?"Принтер на паузе.":(status[0]&0x20)?"Принтер ещё печатает предыдущее задание.":"Принтер сообщает об ошибке.";
        snprintf(message,capacity,"%s Задание не отправлено (статус %02X).",reason,status[0]); goto cleanup;
    }
    rc=libusb_bulk_transfer(h,output,(unsigned char *)payload,length,transferred,15000);
    if (rc!=0 || *transferred!=length) {
        snprintf(message,capacity,"Передача прервана: %d из %d байт. Проверьте принтер перед повторной печатью. USB: %s",*transferred,length,libusb_error_name(rc));
        result=-2; goto cleanup;
    }
    snprintf(message,capacity,"Задание передано принтеру. Проверьте готовые этикетки."); result=0;
cleanup:
    if (claimed) libusb_release_interface(h,iface);
    if (config) libusb_free_config_descriptor(config);
    if (h) libusb_close(h);
    if (list) libusb_free_device_list(list,1);
    libusb_exit(ctx);
    return result;
}

#include <stdlib.h>
typedef struct {
    libusb_context *ctx;
    libusb_device_handle *handle;
    int interface, output, input;
} NiimUSB;

// Discovery only: never opens an unrelated USB device.
int foodlabel_printers(void) {
    libusb_context *ctx=NULL; libusb_device **list=NULL; int found=0;
    if (libusb_init(&ctx)<0) return 0;
    ssize_t count=libusb_get_device_list(ctx,&list);
    for (ssize_t i=0;i<count;i++) {
        struct libusb_device_descriptor d;
        if (libusb_get_device_descriptor(list[i],&d)!=0) continue;
        if (d.idVendor==0x1fc9 && d.idProduct==0x2016) found|=1;
        if (d.idVendor==0x3513 && d.idProduct==2) found|=2;
    }
    if (list) libusb_free_device_list(list,1);
    libusb_exit(ctx); return found;
}
void foodlabel_niim_close(void *opaque) {
    NiimUSB *p=opaque; if (!p) return;
    if (p->handle) { if (p->interface>=0) libusb_release_interface(p->handle,p->interface); libusb_close(p->handle); }
    if (p->ctx) libusb_exit(p->ctx);
    free(p);
}
void *foodlabel_niim_open(char *message,int capacity) {
    NiimUSB *p=calloc(1,sizeof(*p)); if (!p) return NULL;
    p->interface=-1;
    libusb_device **list=NULL; struct libusb_config_descriptor *config=NULL;
    if (libusb_init(&p->ctx)<0) { snprintf(message,capacity,"Не удалось открыть USB."); goto failed; }
    ssize_t n=libusb_get_device_list(p->ctx,&list); libusb_device *target=NULL; int matches=0;
    for (ssize_t i=0;i<n;i++) {
        struct libusb_device_descriptor d;
        if (libusb_get_device_descriptor(list[i],&d)==0 && d.idVendor==0x3513 && d.idProduct==2) { target=list[i]; matches++; }
    }
    if (matches!=1) { snprintf(message,capacity,matches ? "Подключено несколько NIIMBOT. Оставьте только нужный." : "NIIMBOT не найден. Подключите B21 Pro по USB и включите питание."); goto failed; }
    int rc=libusb_open(target,&p->handle);
    if (rc<0) { snprintf(message,capacity,"NIIMBOT недоступен: %s",libusb_error_name(rc)); goto failed; }
    if (libusb_get_active_config_descriptor(target,&config)<0) { snprintf(message,capacity,"Не удалось прочитать USB NIIMBOT."); goto failed; }
    for (int i=0;i<config->bNumInterfaces;i++) {
        for (int j=0;j<config->interface[i].num_altsetting;j++) {
            const struct libusb_interface_descriptor *d=&config->interface[i].altsetting[j];
            if (d->bInterfaceClass!=7 || d->bAlternateSetting!=0) continue;
            int out=-1,in=-1;
            for (int k=0;k<d->bNumEndpoints;k++) {
                const struct libusb_endpoint_descriptor *e=&d->endpoint[k];
                if ((e->bmAttributes&3)!=LIBUSB_TRANSFER_TYPE_BULK) continue;
                if (e->bEndpointAddress&0x80) in=e->bEndpointAddress; else out=e->bEndpointAddress;
            }
            if (out<0 || in<0) continue;
            rc=libusb_claim_interface(p->handle,d->bInterfaceNumber);
            if (rc<0) { snprintf(message,capacity,"NIIMBOT занят. Закройте другие программы печати: %s",libusb_error_name(rc)); goto failed; }
            p->interface=d->bInterfaceNumber; p->input=in; p->output=out;
            unsigned char id[256]={0};
            int length=libusb_control_transfer(p->handle,0xa1,0,0,p->interface,id,255,2000);
            if (length<=2 || !strstr((char*)id+2,"MFG:NIIMBOT;") || !strstr((char*)id+2,"MDL: B21_Pro;")) {
                snprintf(message,capacity,"USB-устройство не подтвердило B21 Pro."); goto failed;
            }
            libusb_free_config_descriptor(config); libusb_free_device_list(list,1); return p;
        }
    }
    snprintf(message,capacity,"Не найден USB-интерфейс печати NIIMBOT.");
failed:
    if (config) libusb_free_config_descriptor(config);
    if (list) libusb_free_device_list(list,1);
    foodlabel_niim_close(p); return NULL;
}
int foodlabel_niim_transfer(void *opaque,int writing,uint8_t *bytes,int length,int *transferred) {
    NiimUSB *p=opaque; *transferred=0;
    if (!p || !bytes || length<=0 || length>512) return LIBUSB_ERROR_INVALID_PARAM;
    return libusb_bulk_transfer(p->handle,writing ? p->output : p->input,bytes,length,transferred,writing ? 3000 : 1000);
}
