;
; Laboratorio1-Micros.asm
;
; Created: 2/10/2025 9:45:05 AM
; Author : jargu
;

.include "M328PDEF.inc"
.cseg
.org 0x0000

// Configuración de la pila
LDI R16, LOW(RAMEND)
OUT SPL, R16  // Cargar 0xFF a Stack Pointer Low
LDI R16, HIGH(RAMEND)
OUT SPH, R16  // Cargar 0x08 a Stack Pointer High

// Configuración de puertos
Setup:
	// PORTD como entrada (botones)
	LDI		R16, 0x00  // Bits apagados en DDRD indican entrada
	OUT		DDRD, R16  
	LDI		R16, 0xFF  // Bits encendidos para habilitar pull-ups
	OUT		PORTD, R16 

	// PORTB como salida (contador 1)
	LDI		R16, 0xFF  // Bits encendidos en DDRB indican salida
	OUT		DDRB, R16  
	LDI		R16, 0x00  // Valor inicial en PORTB
	OUT		PORTB, R16  

	// PORTC como salida (contador 2)
	LDI		R16, 0xFF  // Bits encendidos en DDRC indican salida
	OUT		DDRC, R16  
	LDI		R16, 0x00  // Valor inicial en PORTC
	OUT		PORTC, R16  

	// Guardar estado de botones
	LDI		R17, 0xFF // Contador1

LOOP: 
	//Lectura de botones 
	IN		R16, PIND
	CP		R17, R16 
	BREQ	LOOP
	CALL	DELAY 
	IN		R16, PIND 
	CP		R17, R16 
	BREQ	LOOP
	MOV		R17, R16 

	CALL CONTADOR1
	CALL CONTADOR2
	RJMP LOOP

// -------------------- SUBRUTINA: CONTADOR 1 --------------------

CONTADOR1: 
	CPI		R16, 0xFB  // Botón INCREMENTAR1 (bit 2)
	BREQ	INCREMENTAR1
	CPI		R16, 0xF7  // Botón DECREMENTAR1 (bit 3)
	BREQ	DECREMENTAR1

FIN_CONTADOR1:
	RET  

INCREMENTAR1:
	IN		R18, PORTB  
	INC		R18  
	OUT		PORTB, R18  
	RET  

DECREMENTAR1: 
	IN		R18, PORTB 
	DEC		R18 
	OUT		PORTB, R18 
	RET

// -------------------- SUBRUTINA: CONTADOR 2 --------------------

CONTADOR2:

	CPI		R17, 0xEF // Botón INCREMENTAR2 (bit 4)
	BREQ	INCREMENTAR2
	CPI		R16, 0xDF  // Botón DECREMENTAR (bit 5)
	BREQ	DECREMENTAR2

FIN_CONTADOR2:
	RET

INCREMENTAR2:
	IN		R18, PORTC  
	INC		R18  
	OUT		PORTC, R18  
	RET  

DECREMENTAR2:
	IN		R18, PORTC  
	DEC		R18  
	OUT		PORTC, R18  
	RET

// -------------------- SUBRUTINA: DELAY (Antirrebote) --------------------

DELAY:
	LDI		R18, 0
SUBDELAY1:
	INC		R18
	CPI		R18, 0
	BRNE	SUBDELAY1
	LDI		R18, 0
SUBDELAY2:
	INC		R18
	CPI		R18, 0
	BRNE	SUBDELAY2
	LDI		R18, 0
SUBDELAY3:
	INC		R18
	CPI		R18, 0
	BRNE	SUBDELAY3
	RET