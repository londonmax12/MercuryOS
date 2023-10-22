#include "stdint.h"
#include "stdio.h"

void _cdecl cstart_(uint16_t bootDrive)
{
    printf("Hello %s from C%c\r\n", "World", '!');
    for (;;);
}