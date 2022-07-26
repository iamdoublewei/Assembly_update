/* --COPYRIGHT--,BSD_EX
 * Copyright (c) 2015, Texas Instruments Incorporated
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 * *  Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *
 * *  Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * *  Neither the name of Texas Instruments Incorporated nor the names of
 *    its contributors may be used to endorse or promote products derived
 *    from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
 * THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
 * PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR
 * CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
 * EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
 * PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS;
 * OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
 * WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
 * OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
 * EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 *
 *******************************************************************************
 *
 *                       MSP430 CODE EXAMPLE DISCLAIMER
 *
 * MSP430 code examples are self-contained low-level programs that typically
 * demonstrate a single peripheral function or device feature in a highly
 * concise manner. For this the code may rely on the device's power-on default
 * register values and settings such as the clock configuration and care must
 * be taken when combining code from several examples to avoid potential side
 * effects. Also see www.ti.com/grace for a GUI- and www.ti.com/msp430ware
 * for an API functional library-approach to peripheral configuration.
 *
 * --/COPYRIGHT--*/
//******************************************************************************
//  MSP430FR5x9x Demo - Toggle P1.0 using software
//
//  Description: Toggle P1.0 using software.
//  ACLK = n/a, MCLK = SMCLK = default DCO
//
//           MSP430FR5994
//         ---------------
//     /|\|               |
//      | |               |
//      --|RST            |
//        |               |
//        |           P1.0|-->LED
//
//   William Goh
//   Texas Instruments Inc.
//   October 2015
//   Built with IAR Embedded Workbench V6.30 & Code Composer Studio V6.1
//******************************************************************************
extern "C"{
#include "cheader.h"
}
#include <msp430.h>
#include "cc1101.h"
#include <string.h>

uint8_t tx_buffer[61]={0};
uint8_t packet_size;
volatile uint8_t flag;

void main(void)
{
    WDTCTL = WDTPW | WDTHOLD;               // Stop WDT
    PM5CTL0 &= ~LOCKLPM5;                   // Disable the GPIO power-on default high-impedance mode
                                            // to activate previously configured port settings

    // Configure GPIO
    P1OUT &= ~BIT0;                         // Clear P1.0 output latch for a defined power-on state
    P1DIR |= BIT0;                          // Set P1.0 to output direction

    // Create a packet of data
    tx_buffer[0] = 3;       // header low
    tx_buffer[1] = 0;       // header high
    tx_buffer[2] = 154;     // destination low: 0x9A
    tx_buffer[3] = 66;      // destination high: 0x42
    tx_buffer[4] = 5;       // length low
    tx_buffer[5] = 0;       // length high
    tx_buffer[6] = 61;     // data 1 low: 0x3D
    tx_buffer[7] = 64;     // data 1 high: 0x40
    tx_buffer[8] = 231;     // data 2 low: 0xE7
    tx_buffer[9] = 0;     // data 2 high: 0x00
    tx_buffer[10] = 60;     // data 3 low: 0x3C
    tx_buffer[11] = 64;     // data 3 high: 0x40
    tx_buffer[12] = 12;     // data 4 low: 0x0C
    tx_buffer[13] = 0;     // data 4 high: 0x00
    tx_buffer[14] = 12;     // data 5 low: 0x0C
    tx_buffer[15] = 93;     // data 5 high: 0x5D
    packet_size = 16;
    delay(1);

    Radio.Init();
    Radio.SetDataRate(5); // Needs to be the same in Tx and Rx
    Radio.SetLogicalChannel(1); // Needs to be the same in Tx and Rx
    Radio.SetTxPower(0);

    while(1) {
        Radio.SendData(tx_buffer, packet_size);
        test();
        delay(1);
        Radio.Idle();
        delay(50);
    }
}
