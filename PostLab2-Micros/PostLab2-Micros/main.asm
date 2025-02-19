.include "M328PDEF.inc"
.cseg
.org 0x0000

.def COUNTER = R20       ; Contador de 4 bits (valor mostrado en PORTC, bits 0 a 3)
.def TEMP    = R16       ; Registro temporal
.def OVCNT   = R21       ; Contador de overflow de Timer0


;---------------------------------
; Configuración de la pila
    LDI     TEMP, LOW(RAMEND)
    OUT     SPL, TEMP
    LDI     TEMP, HIGH(RAMEND)
    OUT     SPH, TEMP

    ; Inicializar la tabla de dígitos en la memoria a partir de 0x0100
    LDI     R18, 0b0000001 ; 0 
    LDI     XL, 0x00 
    LDI     XH, 0x01
    ST      X+, R18 

    LDI     R18, 0b1001111 ; 1 
    ST      X+, R18
    LDI     R18, 0b0010010 ; 2
    ST      X+, R18 
    LDI     R18, 0b0000110 ; 3 
    ST      X+, R18 
    LDI     R18, 0b1001100 ; 4 
    ST      X+, R18 
    LDI     R18, 0b0100100 ; 5 
    ST      X+, R18 
    LDI     R18, 0b0100000 ; 6 
    ST      X+, R18
    LDI     R18, 0b0001111 ; 7 
    ST      X+, R18
    LDI     R18, 0b0000000 ; 8 
    ST      X+, R18
    LDI     R18, 0b0000100 ; 9 
    ST      X+, R18    
    LDI     R18, 0b0001000 ; A
    ST      X+, R18
    LDI     R18, 0b1100000 ; B
    ST      X+, R18
    LDI     R18, 0b0110001 ; C
    ST      X+, R18
    LDI     R18, 0b1000010 ; D
    ST      X+, R18
    LDI     R18, 0b0110000 ; E
    ST      X+, R18
    LDI     R18, 0b0111000 ; F
    ST      X+, R18 

;---------------------------------

; Configuración del MCU
SETUP:
    ; Configurar el prescaler principal
    LDI     TEMP, (1 << CLKPCE)
    STS     CLKPR, TEMP          ; Habilitar cambio de prescaler
    LDI     TEMP, 0b00000100
    STS     CLKPR, TEMP          ; Configurar prescaler = 16 (16MHz/16 = 1MHz)

    ; Inicializar Timer0
    CALL    INIT_TMR0

    ; Configurar los pines PC0-PC3 de PORTC como salidas (para mostrar el contador)
    LDI     TEMP, 0x0F           ; 0000 1111
    OUT     DDRC, TEMP

    ; Configurar los pines PD0-PD7 de PORTD como salidas 
    LDI     TEMP, 0xFF 
    OUT     DDRD, TEMP

    ; Configurar los pines PB2-PB3 de PORTB como entradas y PB5 como salida
    LDI     TEMP, 0b00100000     ; 0010 0000
    OUT     DDRB, TEMP
	LDI		TEMP, 0b11011111 
	OUT		PORTB, TEMP ; Configuramos como pull-ups

    ; Inicializar el contador y el contador de overflows a 0
    CLR     COUNTER
    CLR     OVCNT

    ; Inicializar el índice del display (almacenado en R22) a 0
    LDI     R22, 0x00

	LDI     R17, 0xFF       ; Valor de reposo (sin botón presionado)


    ; Salto al bucle principal
    

LOOP: 
    CALL    CONTADOR 
    CALL    DISPLAY
    RJMP    LOOP

;---------------------------------
; Subrutina CONTADOR:
CONTADOR:
    ; Esperar a que se produzca el overflow del Timer0 (bit TOV0 en TIFR0)
WAIT_OVERFLOW:
    IN      TEMP, TIFR0         
    SBRS    TEMP, TOV0  
    RET        

    ; Se detectó overflow: limpiar la bandera escribiendo 1 en TIFR0
    SBI     TIFR0, TOV0

    ; Recargar TCNT0 con 158 para obtener ~100ms hasta el siguiente overflow
    LDI     TEMP, 158 
    OUT     TCNT0, TEMP

    ; Incrementar el contador de overflows
    INC     OVCNT
    CPI     OVCNT, 10           ; 10 * 100ms = 1s
    BRNE    ACTUALIZA_PORT      ; Si aún no han pasado 10 overflows, continuar

    ; Si OVCNT == 10, reiniciarlo y aumentar el contador de 4 bits
    CLR     OVCNT
    INC     COUNTER

// Aqui compara con el valor del Display
    MOV     R24, R22         
    CP      R24, COUNTER     
    BREQ    RESET_COUNTER     //Salta a etiqueta para resetear COUNTER

// Si no son iguales, operar overflow
    CPI     COUNTER, 16       
    BRNE    ACTUALIZA_PORT  // Si no son iguales, seguir
    CLR     COUNTER       // Si son iguales, limpiar y seguir    
    RJMP    ACTUALIZA_PORT    

RESET_COUNTER:
    OUT     PORTC, COUNTER  
	SBI		PINB, 5
    CLR     COUNTER           
    RJMP    LOOP             

ACTUALIZA_PORT:
    OUT     PORTC, COUNTER    ; Actualizar la salida en PORTC
    RET



	

;---------------------------------
; Subrutina: Inicializar Timer0
INIT_TMR0:
    ; Configurar Timer0 en modo normal con prescaler = 1024:
    LDI     TEMP, (1<<CS02) | (1<<CS00)
    OUT     TCCR0B, TEMP

    ; Precargar TCNT0 para overflow en ~100ms (256 - 98 = 158)
    LDI     TEMP, 158
    OUT     TCNT0, TEMP

    RET

;------------------------------------------------------------------------------------
; Subrutina DISPLAY:
; Se encarga de leer los botones (PB2 para incrementar y PB3 para decrementar)
; y actualizar el display con el valor almacenado indirectamente.
DISPLAY:

LECTURA: 
    ; Lectura de botones 
    IN      R16, PINB
    CP      R17, R16 
    BRNE    SEGUIR
    RET

SEGUIR:
    CALL    DELAY 
    IN      R16, PINB
    CP      R17, R16 
    BREQ    LECTURA
    MOV     R17, R16 

    ; Verificar el botón de incremento (PB2)
    SBRC    R16, 2      
	RJMP    VERIFICAR_INC    
    RJMP    INCREMENTAR          

VERIFICAR_INC:
    ; Verificar el botón de decremento (PB3)
    SBRC    R16, 3          
    RJMP    LECTURA           
    RJMP    DECREMENTAR     

INCREMENTAR: 
    INC     R22
    CPI     R22, 0x10
    BRLO    CONTINUAR_INC
    LDI     R22, 0x00
CONTINUAR_INC:
    ; Actualizar el display (usando la tabla indirecta en 0x0100)
    LDI     XL, 0x00 
    LDI     XH, 0x01
    ADD     XL, R22 
    LD      R18, X
    OUT     PORTD, R18
    RJMP    LOOP

DECREMENTAR:
    CPI     R22, 0x00        ; Compara R22 con 0
    BREQ    UNDERFLOW        ; Si R22 es 0, se envuelve a 0x0F
    DEC     R22              ; Decrementa R22 si no es 0
    RJMP    update_disp_dec
UNDERFLOW:
    LDI     R22, 0x0F        ; Si R22 era 0, se establece en 0x0F
update_disp_dec:
    ; Actualiza el display con el nuevo valor de R22
    LDI     XL, 0x00         ; Dirección base (0x0100)
    LDI     XH, 0x01
    ADD     XL, R22
    LD      R18, X
    OUT     PORTD, R18
    RJMP    LOOP

;-------------------- SUBRUTINA: DELAY (Antirrebote) --------------------
DELAY:
    LDI     R18, 0
SUBDELAY1:
    INC     R18
    CPI     R18, 0
    BRNE    SUBDELAY1
    LDI     R18, 0
SUBDELAY2:
    INC     R18
    CPI     R18, 0
    BRNE    SUBDELAY2
    LDI     R18, 0
SUBDELAY3:
    INC     R18
    CPI     R18, 0
    BRNE    SUBDELAY3
    RET