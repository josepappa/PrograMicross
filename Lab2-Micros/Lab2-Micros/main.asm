
; Lab2-Micros.asm
;
; Created: 2/12/2025 4:40:51 PM
; Author : José Eduardo Argueta Pappa
; Carné: 23149
; Descripción: El presente código utiliza registros de almacenamiento indirecto para manejar un display de 7 segmentos. 


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
	//PORTD como salidas 
	LDI		R16, 0xFF 
	OUT		DDRD, R16 
	
	//PORTB como entradas 
	LDI		R16, 0x00 
	OUT		DDRB, R16 
	LDI		R16, 0xFF //Configurar Pull-ups 
	OUT		PORTB, R16  

	//El registro indirecto X se apunta a la direccion 0x0100

	LDI		R18, 0b0000001 // 0 
	LDI		XL, 0x00 
	LDI		XH, 0x01
	ST		X+, R18 

	LDI		R18, 0b1001111 // 1 
	ST		X+, R18
	LDI		R18, 0b0010010 // 2
	ST		X+, R18 
	LDI		R18, 0b0000110 // 3 
	ST		X+, R18 
	LDI		R18, 0b1001100 // 4 
	ST		X+, R18 
	LDI		R18, 0b0100100 // 5 
	ST		X+, R18 
	LDI		R18, 0b0100000 // 6 
	ST		X+, R18
	LDI		R18, 0b0001111 // 7 
	ST		X+, R18
	LDI		R18, 0b0000000 // 8 
	ST		X+, R18
	LDI		R18, 0b0000100 // 9 
	ST		X+, R18	
	LDI		R18, 0b0001000 // A
	ST		X+, R18
	LDI		R18, 0b1100000 // B
	ST		X+, R18
	LDI		R18, 0b0110001 // C
	ST		X+, R18
	LDI		R18, 0b1000010 // D
	ST		X+, R18
	LDI		R18, 0b0110000 //E
	ST		X+, R18
	LDI		R18, 0b0111000 //F
	ST		X+, R18 

	// Guardar estado de botones
	LDI		R17, 0xFF

	//Incremento o decremento relativo indirecto
	LDI		R22, 0x00 
LOOP: 
	//Lectura de botones 
	IN		R16, PINB
	CP		R17, R16 
	BREQ	LOOP
	CALL	DELAY 
	IN		R16, PINB
	CP		R17, R16 
	BREQ	LOOP
	MOV		R17, R16 

    ; Verificar el botón de incremento (PB2)
    SBRC    R16, 2          
    RJMP    VERIFICAR_INC 
    RJMP    INCREMENTAR     

VERIFICAR_INC:
    ; Verificar el botón de decremento (PB3)
    SBRC    R16, 3          
    RJMP    LOOP           
    RJMP    DECREMENTAR     

	
INCREMENTAR: 
	INC		R22
	CPI		R22, 0x10
	BRLO	CONTINUAR_INC
	LDI		R22, 0x00
	CONTINUAR_INC:
	LDI		XL, 0x00 
	LDI		XH, 0x01
	ADD		XL, R22 
	LD		R18, X
	OUT		PORTD, R18
	RJMP	LOOP

DECREMENTAR:
    CPI     R22, 0x00        ; Compara R20 con 0
    BREQ    UNDERFLOW         ; Si R20 es 0, se debe envolver (wrap-around) a 0x0F
    DEC     R22              ; Decrementa R20 si no es 0
    RJMP    update_disp_dec
UNDERFLOW:
    LDI     R22, 0x0F        ; Si R20 era 0, se establece en 0x0F
update_disp_dec:
    ; Actualiza el display con el nuevo valor de R20
    LDI     XL, 0x00         ; Dirección baja base (0x0100)
    LDI     XH, 0x01         ; Dirección alta base
    ADD     XL, R22          ; Se suma el índice para obtener la dirección correcta
    LD      R18, X           ; Carga el patrón del dígito
    OUT     PORTD, R18       ; Envía el patrón a PORTD
    RJMP    LOOP             ; Vuelve al loop principal



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



