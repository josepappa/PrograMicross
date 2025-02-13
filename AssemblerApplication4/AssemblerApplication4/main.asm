;
; PostLaboratorio1-Micros.asm
;
; Created: 2/12/2025 12:00:59 AM
; Author : jargu
;


; Replace with your application code
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
	// PORTB como entrada (botones)
	LDI		R16, 0x00  // Bits apagados en DDRB indican entrada
	OUT		DDRB, R16  
	LDI		R16, 0xFF  // Bits encendidos para habilitar pull-ups
	OUT		PORTB, R16 

	// PORTD como salida (contador 1)
	LDI		R16, 0xFF  // Bits encendidos en DDRD indican salida
	OUT		DDRD, R16  
	LDI		R16, 0x00  // Valor inicial en PORTD
	OUT		PORTD, R16  

	// PORTC como salida (contador 2)
	LDI		R16, 0xFF  // Bits encendidos en DDRC indican salida
	OUT		DDRC, R16  
	LDI		R16, 0x00  // Valor inicial en PORTC
	OUT		PORTC, R16  

	// Guardar estado de botones
	LDI		R17, 0xFF
	LDI		R16, 0x00
	LDI		R19, 0x00
	LDI		R20, 0x00
	LDI		R21, 0x00

LOOP: 

// Combinar ambos contadores en R21 y mostrar en PORTD
	ANDI    R19, 0x0F
    MOV     R21, R19     
	MOV		R22, R20
    ANDI    R22, 0x0F
    SWAP    R22          
    OR      R21, R22
	OUT		PORTD, R21
	//Lectura de botones 

	IN		R16, PINB
	CP		R17, R16 
	BREQ	LOOP
	CALL	DELAY 
	IN		R16, PINB 
	CP		R17, R16 
	BREQ	LOOP
	MOV		R17, R16 

	CALL CONTADOR1

SIGCONT:
	CALL CONTADOR2
SIGSUM:
	CALL SUMADOR
// -------------------- SUBRUTINA: CONTADOR 1 --------------------

CONTADOR1: 
	CALL INCREMENTAR1  

INCREMENTAR1:  
	SBRC    R16, 0  //Botón de Incremento presionado (bit 0)   
	CALL    DECREMENTAR1 // bit 0 no está presionado 
    INC		R19
    CALL    DECREMENTAR1 

DECREMENTAR1: 
	SBRC    R16, 1   
	RJMP	SIGCONT
    DEC		R19
    RJMP	SIGCONT
// -------------------- SUBRUTINA: CONTADOR 2 --------------------

CONTADOR2:
	CALL INCREMENTAR2

INCREMENTAR2:  
	SBRC    R16, 2     
	CALL    DECREMENTAR2
    INC		R20
    CALL    DECREMENTAR2

DECREMENTAR2: 
	SBRC    R16, 3   
	RJMP	SIGSUM
    DEC		R20
    RJMP	SIGSUM


//----------------------- SUBRUTINA: SUMADOR ---------------------------
SUMADOR:
	LDI		R23, 0x00
	SBRC    R16, 4  
	RJMP	LOOP
    MOV		R23, R19
	ADD		R23, R20
	OUT		PORTC, R23
    RJMP	LOOP

	

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