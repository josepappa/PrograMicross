; -----------------------------------------------------------------------------
; Proyecto1-Micros.asm
; Fecha: 3/6/2025
; Autor: jargu
; -----------------------------------------------------------------------------

.INCLUDE "m328pdef.inc"

; ----------------- Ajusta según tu reloj (cada overflow ~5ms con prescaler=64) -----------------
.equ   VALOR_TMR0  = 178    ; Valor recargado en TCNT0 para obtener overflow ~5ms

.dseg
.org 0x0110

DD_UN:			.byte 1
DD_DEC:			.byte 1
MM_UN:			.byte 1
MM_DEC:			.byte 1

DIGITO_0:		.byte 1
DIGITO_1:		.byte 1
DIGITO_2:		.byte 1
DIGITO_3:		.byte 1


.cseg

; ----------------- Registros de uso general -----------------

.def   MIN_UN_ALARMA = R8
.def   MIN_DEC_ALARMA = R9 
.def   HORA_UN_ALARMA = R10 
.def   HORA_DEC_ALARMA = R11

.def   DISP_CNT   = R17   ; Contador para multiplexar displays
.def   MIN_UN     = R18   ; Unidades de minuto (0-9)
.def   MIN_DEC    = R19   ; Decenas de minuto (0-5)
.def   HORA_UN    = R20   ; Unidades de hora (0-9)
.def   HORA_DEC   = R21   ; Decenas de hora (0-2)
.def   LED_CNT    = R22   ; Contador para hacer toggle del LED (PD7) cada 500ms
.def   OVCNT     = R23	  ; Contador de overflows para alcanzar 1 segundo
.def   FLAG       = R25   ; Bandera (modo). 0 = MODO_RELOJ
.def   SHOW_DISP0 = R26   ; Código 7-seg para display en PC5
.def   SHOW_DISP1 = R27   ; Código 7-seg para display en PC4
.def   SHOW_DISP2 = R28   ; Código 7-seg para display en PC3
.def   SHOW_DISP3 = R29   ; Código 7-seg para display en PC2

; -----------------------------------------------------------------------------
; Vectores de interrupción
; -----------------------------------------------------------------------------
.ORG 0x0000
    RJMP    INICIO

.ORG 0x0006                 ; ISR PCINT0 (cambio en PORTB)
    RJMP    ISR_PCINT0

.ORG 0x0020                 ; ISR Timer0 (overflow)
    RJMP    ISR_TIMER0

; =============================================================================
; ========================== SETUP  ===========================
; =============================================================================

INICIO:
    ; ---------------- Configuración de la pila ----------------
    LDI     R16, LOW(RAMEND)
    OUT     SPL, R16
    LDI     R16, HIGH(RAMEND)
    OUT     SPH, R16

    ; ---------------- Copiar la tabla de dígitos a SRAM (0x0100) ----------------
    ; Formato: bits PD6..PD0 para el 7-seg, PD7 no se toca (LED)
    LDI     R16, 0b0000001   ; dígito 0
    LDI     ZL, 0x00
    LDI     ZH, 0x01         ; Z -> 0x0100
    ST      Z+, R16

    LDI     R16, 0b1001111   ; dígito 1
    ST      Z+, R16
    LDI     R16, 0b0010010   ; dígito 2
    ST      Z+, R16
    LDI     R16, 0b0000110   ; dígito 3
    ST      Z+, R16
    LDI     R16, 0b1001100   ; dígito 4
    ST      Z+, R16
    LDI     R16, 0b0100100   ; dígito 5
    ST      Z+, R16
    LDI     R16, 0b0100000   ; dígito 6
    ST      Z+, R16
    LDI     R16, 0b0001111   ; dígito 7
    ST      Z+, R16
    LDI     R16, 0b0000000   ; dígito 8
    ST      Z+, R16
    LDI     R16, 0b0000100   ; dígito 9
    ST      Z+, R16

    ; ---------------- Prescaler del reloj del sistema (opcional) ----------------
    LDI     R16, (1<<CLKPCE)
    STS     CLKPR, R16          ; Habilitar cambio en CLKPR
    LDI     R16, 0b00000100     ; Prescaler = 16 => 16MHz/16 = 1MHz
    STS     CLKPR, R16

    ; ---------------- Inicializar Timer0 ----------------
    CALL    INIT_TMR0

    ; ---------------- Configuración de puertos ----------------
    ; PORTD: PD0..PD6 -> segmentos, PD7 -> LED
    LDI     R16, 0xFF
    OUT     DDRD, R16
    LDI     R16, 0x80      ; Apagamos el LED PD7 al inicio
    OUT     PORTD, R16

    ; PORTB: PB0..PB4 -> botones (entradas), PB5 -> buzzer (salida)
    LDI     R16, 0x20
    OUT     DDRB, R16
    LDI     R16, 0x1F      ; Activar pull-ups en PB0..PB4, PB5 apagado
    OUT     PORTB, R16

    ; PORTC: PC2..PC5 -> transistores para displays, PC0..PC1 -> LEDs extra
    LDI     R16, 0x3F
    OUT     DDRC, R16
    LDI     R16, 0x00
    OUT     PORTC, R16

    ; ---------------- Interrupción por cambio de pin (PCINT0) en PB0 ----------------
    LDI     R16, (1<<PCIE0)
    STS     PCICR, R16
    LDI     R16, 0x1F
    STS     PCMSK0, R16

    ; ---------------- Interrupción Timer0 ----------------
    LDI     R16, (1<<TOIE0)
    STS     TIMSK0, R16

    ; ---------------- Inicializar variables ----------------

	LDI		R16, 3
    MOV     HORA_UN_ALARMA, R16		; Iniciar alarma en algun valor
	LDI		R16, 2					
    MOV     HORA_DEC_ALARMA, R16	; Iniciar alarma en algun valor
	CLR     MIN_UN_ALARMA
    CLR     MIN_DEC_ALARMA
    CLR     DISP_CNT
    CLR     MIN_UN
    CLR     MIN_DEC
    CLR     HORA_UN
    CLR     HORA_DEC
    CLR     LED_CNT
    CLR     OVCNT
    CLR     FLAG           
    CLR     SHOW_DISP0
    CLR     SHOW_DISP1
    CLR     SHOW_DISP2
    CLR     SHOW_DISP3
	CLR		R16
	CLR		R2
	CLR		R3				; DD_DEC
	CLR		R4				; MM_UN
	CLR		R5				; MM_DEC

 ; ---------------- Limpiar variables en SRAM ----------------
	LDI		R16, 0X01				; Iniciar fecha en el día 1 de cada mes 
    STS     DD_UN, R16
    STS     DD_DEC, R16
    STS     MM_UN, R16
    STS     MM_DEC, R16
    STS     DIGITO_0, R16
    STS     DIGITO_1, R16
    STS     DIGITO_2, R16
    STS     DIGITO_3, R16
	

    ; ---------------- Habilitar interrupciones globales ----------------
    SEI


; =============================================================================
; ========================== LOOP PRINCIPAL ===========================
; =============================================================================

LOOP:
    ; Si FLAG = 0 => modo reloj, de lo contrario, modo fecha.
    CPI     FLAG, 0 
    BRNE    MOSTRAR_FECHA   ; Si FLAG es diferente de 0, verifico si es fecha
	CBI		PORTC, 0 
	CBI		PORTC, 1


	; comparar si es la ALARMA es igual a la HORA
	CP		HORA_DEC_ALARMA, HORA_DEC		
	BRNE	IR_EXIT_LOOP 
	CP		HORA_UN_ALARMA, HORA_UN
	BRNE	IR_EXIT_LOOP
	CP		MIN_DEC_ALARMA, MIN_DEC
	BRNE	IR_EXIT_LOOP 
	CP		MIN_UN_ALARMA, MIN_UN
	BRNE	IR_EXIT_LOOP
	RJMP	BUZZER

IR_EXIT_LOOP:
	RJMP	EXIT_LOOP
		
	; encender buzzer si la ALARMA y HORA hacen match
BUZZER:
	SBI PORTB, 5
	SBI PORTC, 0 
	SBI PORTC, 1

    RJMP    EXIT_LOOP       ; Si FLAG = 0, se usa el código de reloj (ya implementado en otra parte).



; =============================================================================
; ========================== MOSTRAR FECHA ===========================
; =============================================================================

MOSTRAR_FECHA:
    CPI     FLAG, 1 
    BRNE	IR_CONFIGURAR_HORA		; Si flag no es 1, salto
	RJMP	SEGUIR_MOSTRAR_FECHA


IR_CONFIGURAR_HORA:
	RJMP	CONFIGURAR_HORA
    ; Indicadores visuales para modo fecha:

SEGUIR_MOSTRAR_FECHA:
    SBI     PORTD, 7        ; Enciende LED indicador 
    CBI     PORTC, 0
    CBI     PORTC, 1
	CBI		PORTB, 5
	

; -----------------------------------------------------------------------------
; ------------------------- VERIFICAR MES ----------------------------
; -----------------------------------------------------------------------------

	; Si la unidad de días es 0, verifico si es octubre
	LDI		R16, 0X00
	CP		R4, R16 
	BREQ	VERIFY_OCT
	RJMP	VERIFY_ENERO	

VERIFY_OCT:
	LDI		R16, 0X01
	CP		R5, R16 
	BREQ	GO_OCTUBRE
	RJMP	CARGAR1

VERIFY_ENERO:
; Verificar si es ENERO
	LDI     R16, 0x01     ; Cargar 1 en R16
    CP      R4, R16       ; Comparar R4 con 1
	BREQ    VERIFY_NOV
	RJMP	VERIFY_FEB
	
VERIFY_NOV: 
	LDI		R16, 0X01
	CP		R5, R16
	BREQ	GO_NOVIEMBRE
	RJMP	GO_ENERO


VERIFY_FEB:
; Verificar si es FEBRERO
	LDI		R16, 0X02
	CP		R4, R16
	BREQ	VERIFY_DIC
	RJMP	VERIFY_MAR

VERIFY_DIC:
	LDI		R16, 0X01
	CP		R5, R16 
	BREQ	GO_DICIEMBRE
	RJMP	GO_FEBRERO	

VERIFY_MAR:
; Verificar si es MARZO
	LDI		R16, 0X03 
	CP		R4, R16 
	BREQ	GO_MARZO

; Verificar si es ABRIL
	LDI		R16, 0X04
	CP		R4, R16
	BREQ	GO_ABRIL

; Verificar si es MAYO
	LDI		R16, 0X05 
	CP		R4, R16 
	BREQ	GO_MAYO

; Verificar si es JUNIO
	LDI		R16, 0X06
	CP		R4, R16
	BREQ	GO_JUNIO

; Verificar si es JULIO
	LDI		R16, 0X07
	CP		R4, R16
	BREQ	GO_JULIO

; Verificar si es AGOSTO
	LDI		R16, 0X08
	CP		R4, R16
	BREQ	GO_AGOSTO

; Verificar si es SEPTIEMBRE
	LDI		R16, 0X09
	CP		R4, R16
	BREQ	GO_SEPTIEMBRE

; Verificar si es OCTUBRE
	LDI		R16, 0X09
	CP		R4, R16
	BREQ	GO_OCTUBRE

; Verificar si es NOVIEMBRE
	LDI		R16, 0X09
	CP		R4, R16
	BREQ	GO_NOVIEMBRE

; Verificar si es DICIEMBRE
	LDI		R16, 0X09
	CP		R4, R16
	BREQ	GO_DICIEMBRE


GO_ENERO:
	RJMP	ENERO

GO_FEBRERO:
	RJMP	FEBRERO

GO_MARZO:
	RJMP	MARZO

GO_ABRIL:
	RJMP	ABRIL

GO_MAYO:
	RJMP	MAYO 

GO_JUNIO:
	RJMP	JUNIO

GO_JULIO:
	RJMP	JULIO

GO_AGOSTO:
	RJMP	AGOSTO

GO_SEPTIEMBRE:
	RJMP	SEPTIEMBRE

GO_OCTUBRE:
	RJMP	OCTUBRE

GO_NOVIEMBRE:
	RJMP	NOVIEMBRE

GO_DICIEMBRE:
	RJMP	DICIEMBRE

CARGAR1:
	LDI		R16, 0X01
	MOV		R4, R16		; MM_UN = 1 (para iniciar en enero )

; -----------------------------------------------------------------------------
; ------------------------- ENERO ----------------------------
; -----------------------------------------------------------------------------

ENERO:

	CLR		R16
	MOV		R5, R16		; MM_DEC = 0


    ; Manejo de DD_UN:
    LDS     R16, DD_UN			
	CPI		R16, 0X02			; Comparar UNIDADES con 2 
	BRNE	SEGUIR_DD_UN	
	LDI		R16, 0X03		
	CP		R3, R16				; Comparar DECENAS con 3
	BREQ	IR_FEBRERO			; Si ambas se cumplen, ir a FEBRERO
	LDS     R16, DD_UN			; Recuperar valor de DD_UN (si no se cumplió)
	RJMP	SEGUIR_DD_UN

IR_FEBRERO:		; ------ SE CUMPLÓ QUE 01/31 ------
	LDI		R16, 0X01		
	STS		DD_UN, R16			; Cargar el valor para 1 de febrer0
	MOV		SHOW_DISP0, R16	
	CLR		R3					; Reiniciar DECENAS 
	MOV     SHOW_DISP1, R3	
	RJMP	FEBRERO				; IR A FEBRERO

SEGUIR_DD_UN:	; ------ NO SE CUMPLÓ ------
    CPI     R16, 10				 
    BRGE    ROLL_OVER			 ; Si no, salta a almacenar DD_UN sin rollover
	RJMP	NO_ROLLOVER

ROLL_OVER:
    ; Rollover: DD_UN llegó a 10
    CLR     R16					 ; R16 = 0 (nuevo DD_UN)
    STS     DD_UN, R16			; Guarda DD_UN = 0
    MOV     SHOW_DISP0, R16		; Muestra 0 en el display de unidades de día
	
    INC     R3             
    MOV     SHOW_DISP1, R3		; Muestra DD_DEC en el display de decenas de día
    RJMP    EXIT_LOOP


NO_ROLLOVER:
    ; Si DD_UN < 10, simplemente almacena el valor y lo muestra
    STS     DD_UN, R16
    MOV     SHOW_DISP0, R16
    MOV     SHOW_DISP1, R3
	MOV		SHOW_DISP2, R4
	MOV		SHOW_DISP3, R5

	RJMP    LOOP

; -----------------------------------------------------------------------------
; ------------------------- FEBRERO ----------------------------
; -----------------------------------------------------------------------------

FEBRERO:
	
	; DD_DEC vuelve a 0
	; Siempre se muestra que está el 2 de febrero
	LDI		R16, 0X02
	MOV		R4, R16
	MOV		SHOW_DISP2, R4
	CLR		R5
	MOV		SHOW_DISP3, R5

	LDS		R16, DD_UN			; Cargo el valor actual de DD_UN
	CPI		R16, 9				; Comparo UNIDADES con 9
	BRNE	SEGUIR_DD_UN_FEB	
	LDI		R16, 0X02			
	CP		R3, R16				; Comparo DECENAS con 2
	BREQ	IR_MARZO
	LDS     R16, DD_UN			; Recuperar valor de DD_UN
	RJMP	SEGUIR_DD_UN_FEB


IR_MARZO:		; ------ SE CUMPLIÓ QUE 02/28 ------
	LDI		R16, 0X01
	STS		DD_UN, R16
	MOV		SHOW_DISP0, R16
	CLR		R3
	MOV     SHOW_DISP1, R3
	RJMP	MARZO

SEGUIR_DD_UN_FEB:	; ------ NO SE CUMPLIÓ ------
	CPI		R16, 10
	BRNE	NO_ROLLOVER_FEB
    CLR     R16             ; R16 = 0 (nuevo DD_UN)
    STS     DD_UN, R16      ; Guarda DD_UN = 0
    MOV     SHOW_DISP0, R16 ; Muestra 0 en el display de unidades de día
	
    INC     R3             
    MOV     SHOW_DISP1, R3  ; Muestra DD_DEC en el display de decenas de día
    RJMP    EXIT_LOOP

NO_ROLLOVER_FEB:
	STS     DD_UN, R16
    MOV     SHOW_DISP0, R16
    MOV     SHOW_DISP1, R3
	MOV		SHOW_DISP2, R4
	MOV		SHOW_DISP3, R5

	RJMP	EXIT_LOOP 
	
; -----------------------------------------------------------------------------
; ------------------------- MARZO ----------------------------
; -----------------------------------------------------------------------------
MARZO:

	LDI		R16, 0X03
	MOV		R4, R16
	MOV		SHOW_DISP2, R4
	CLR		R5
	MOV		SHOW_DISP3, R5

	; Manejo de DD_UN:
    LDS     R16, DD_UN			; R16 ? DD_UN
	CPI		R16, 0X02			; Comparar UNIDADES con 2 
	BRNE	SEGUIR_DD_UN_MAR	
	LDI		R16, 0X03		
	CP		R3, R16				; Comparar DECENAS con 3
	BREQ	IR_ABRIL			; Si ambas se cumplen, ir a ABRIL
	LDS     R16, DD_UN			; Recuperar valor de DD_UN (si no se cumplió)
	RJMP	SEGUIR_DD_UN_MAR

IR_ABRIL:		; ------ SE CUMPLÓ QUE 03/31 ------
	LDI		R16, 0X01		
	STS		DD_UN, R16			; Cargar el valor para 1 de ABRIL
	MOV		SHOW_DISP0, R16	
	CLR		R3					; Reiniciar DECENAS 
	MOV     SHOW_DISP1, R3	
	RJMP	ABRIL				; IR A ABRIL

SEGUIR_DD_UN_MAR:	; ------ NO SE CUMPLÓ ------
    CPI     R16, 10				 ; 
    BRNE    NO_ROLLOVER_MAR			 ; Si no, salta a almacenar DD_UN sin rollover

    ; Rollover: DD_UN llegó a 10
    CLR     R16					 ; R16 = 0 (nuevo DD_UN)
    STS     DD_UN, R16			; Guarda DD_UN = 0
    MOV     SHOW_DISP0, R16		; Muestra 0 en el display de unidades de día
	
    INC     R3             
    MOV     SHOW_DISP1, R3		; Muestra DD_DEC en el display de decenas de día
    RJMP    EXIT_LOOP


NO_ROLLOVER_MAR:
    ; Si DD_UN < 10, simplemente almacena el valor y lo muestra
    STS     DD_UN, R16
    MOV     SHOW_DISP0, R16
    MOV     SHOW_DISP1, R3
	MOV		SHOW_DISP2, R4
	MOV		SHOW_DISP3, R5

	RJMP	EXIT_LOOP

; -----------------------------------------------------------------------------
; ------------------------- ABRIL ----------------------------
; -----------------------------------------------------------------------------
ABRIL:
	LDI		R16, 0X04
	MOV		R4, R16
	MOV		SHOW_DISP2, R4
	CLR		R5
	MOV		SHOW_DISP3, R5

	; Manejo de DD_UN:
    LDS     R16, DD_UN			; R16 ? DD_UN
	CPI		R16, 0X01			; Comparar UNIDADES con 2 
	BRNE	SEGUIR_DD_UN_ABR	
	LDI		R16, 0X03		
	CP		R3, R16				; Comparar DECENAS con 3
	BREQ	IR_MAYO			    ; Si ambas se cumplen, ir a MAYO
	LDS     R16, DD_UN			; Recuperar valor de DD_UN (si no se cumplió)
	RJMP	SEGUIR_DD_UN_ABR

IR_MAYO:		; ------ SE CUMPLÓ QUE 04/30 ------
	LDI		R16, 0X01		
	STS		DD_UN, R16			; Cargar el valor para 1 de MAYO
	MOV		SHOW_DISP0, R16	
	CLR		R3					; Reiniciar DECENAS 
	MOV     SHOW_DISP1, R3	
	RJMP	MAYO				; IR A MAYO

SEGUIR_DD_UN_ABR:	; ------ NO SE CUMPLÓ ------
    CPI     R16, 10				 ; 
    BRNE    NO_ROLLOVER_ABR			 ; Si no, salta a almacenar DD_UN sin rollover

    ; Rollover: DD_UN llegó a 10
    CLR     R16					 ; R16 = 0 (nuevo DD_UN)
    STS     DD_UN, R16			; Guarda DD_UN = 0
    MOV     SHOW_DISP0, R16		; Muestra 0 en el display de unidades de día
	
    INC     R3             
    MOV     SHOW_DISP1, R3		; Muestra DD_DEC en el display de decenas de día
    RJMP    EXIT_LOOP


NO_ROLLOVER_ABR:
    ; Si DD_UN < 10, simplemente almacena el valor y lo muestra
    STS     DD_UN, R16
    MOV     SHOW_DISP0, R16
    MOV     SHOW_DISP1, R3
	MOV		SHOW_DISP2, R4
	MOV		SHOW_DISP3, R5

	RJMP	EXIT_LOOP

; -----------------------------------------------------------------------------
; ------------------------- MAYO ----------------------------
; -----------------------------------------------------------------------------

MAYO:
	LDI		R16, 0X05
	MOV		R4, R16
	MOV		SHOW_DISP2, R4
	CLR		R5
	MOV		SHOW_DISP3, R5

	; Manejo de DD_UN:
    LDS     R16, DD_UN			; R16 ? DD_UN
	CPI		R16, 0X02			; Comparar UNIDADES con 2 
	BRNE	SEGUIR_DD_UN_MAY	
	LDI		R16, 0X03		
	CP		R3, R16				; Comparar DECENAS con 3
	BREQ	IR_JUN				; Si ambas se cumplen, ir a JUNIO
	LDS     R16, DD_UN			; Recuperar valor de DD_UN (si no se cumplió)
	RJMP	SEGUIR_DD_UN_MAY

IR_JUN:		; ------ SE CUMPLÓ QUE 05/31 ------
	LDI		R16, 0X01		
	STS		DD_UN, R16			; Cargar el valor para 1 de JUNIO
	MOV		SHOW_DISP0, R16	
	CLR		R3					; Reiniciar DECENAS 
	MOV     SHOW_DISP1, R3	
	RJMP	JUNIO				; IR A JUNIO

SEGUIR_DD_UN_MAY:	; ------ NO SE CUMPLÓ ------
    CPI     R16, 10				 ; 
    BRNE    NO_ROLLOVER_MAY			 ; Si no, salta a almacenar DD_UN sin rollover

    ; Rollover: DD_UN llegó a 10
    CLR     R16					 ; R16 = 0 (nuevo DD_UN)
    STS     DD_UN, R16			; Guarda DD_UN = 0
    MOV     SHOW_DISP0, R16		; Muestra 0 en el display de unidades de día
	
    INC     R3             
    MOV     SHOW_DISP1, R3		; Muestra DD_DEC en el display de decenas de día
    RJMP    EXIT_LOOP


NO_ROLLOVER_MAY:
    ; Si DD_UN < 10, simplemente almacena el valor y lo muestra
    STS     DD_UN, R16
    MOV     SHOW_DISP0, R16
    MOV     SHOW_DISP1, R3
	MOV		SHOW_DISP2, R4
	MOV		SHOW_DISP3, R5

	RJMP	EXIT_LOOP

; -----------------------------------------------------------------------------
; ------------------------- JUNIO ----------------------------
; -----------------------------------------------------------------------------

JUNIO:
	LDI		R16, 0X06
	MOV		R4, R16
	MOV		SHOW_DISP2, R4
	CLR		R5
	MOV		SHOW_DISP3, R5

	; Manejo de DD_UN:
    LDS     R16, DD_UN			; R16 ? DD_UN
	CPI		R16, 0X01			; Comparar UNIDADES con 1
	BRNE	SEGUIR_DD_UN_JUN	
	LDI		R16, 0X03		
	CP		R3, R16				; Comparar DECENAS con 3
	BREQ	IR_JULIO		    ; Si ambas se cumplen, ir a JULIO
	LDS     R16, DD_UN			; Recuperar valor de DD_UN (si no se cumplió)
	RJMP	SEGUIR_DD_UN_JUN

IR_JULIO:		; ------ SE CUMPLÓ QUE 06/30 ------
	LDI		R16, 0X01		
	STS		DD_UN, R16			; Cargar el valor para 1 de JULIO
	MOV		SHOW_DISP0, R16	
	CLR		R3					; Reiniciar DECENAS 
	MOV     SHOW_DISP1, R3	
	RJMP	JULIO				; IR A JULIO

SEGUIR_DD_UN_JUN:	; ------ NO SE CUMPLÓ ------
    CPI     R16, 10				 ; 
    BRNE    NO_ROLLOVER_JUN		 ; Si no, salta a almacenar DD_UN sin rollover

    ; Rollover: DD_UN llegó a 10
    CLR     R16					 ; R16 = 0 (nuevo DD_UN)
    STS     DD_UN, R16			; Guarda DD_UN = 0
    MOV     SHOW_DISP0, R16		; Muestra 0 en el display de unidades de día
	
    INC     R3             
    MOV     SHOW_DISP1, R3		; Muestra DD_DEC en el display de decenas de día
    RJMP    EXIT_LOOP


NO_ROLLOVER_JUN:
    ; Si DD_UN < 10, simplemente almacena el valor y lo muestra
    STS     DD_UN, R16
    MOV     SHOW_DISP0, R16
    MOV     SHOW_DISP1, R3
	MOV		SHOW_DISP2, R4
	MOV		SHOW_DISP3, R5

	RJMP	EXIT_LOOP

; -----------------------------------------------------------------------------
; ------------------------- JULIO ----------------------------
; -----------------------------------------------------------------------------

JULIO:
	LDI		R16, 0X07
	MOV		R4, R16
	MOV		SHOW_DISP2, R4
	CLR		R5
	MOV		SHOW_DISP3, R5

	; Manejo de DD_UN:
    LDS     R16, DD_UN			; R16 ? DD_UN
	CPI		R16, 0X02			; Comparar UNIDADES con 2 
	BRNE	SEGUIR_DD_UN_JUL	
	LDI		R16, 0X03		
	CP		R3, R16				; Comparar DECENAS con 3
	BREQ	IR_AGO				; Si ambas se cumplen, ir a JUNIO
	LDS     R16, DD_UN			; Recuperar valor de DD_UN (si no se cumplió)
	RJMP	SEGUIR_DD_UN_JUL

IR_AGO:		; ------ SE CUMPLÓ QUE 07/31 ------
	LDI		R16, 0X01		
	STS		DD_UN, R16			; Cargar el valor para 1 de AGOSTO
	MOV		SHOW_DISP0, R16	
	CLR		R3					; Reiniciar DECENAS 
	MOV     SHOW_DISP1, R3	
	RJMP	AGOSTO				; IR A AGOSTO

SEGUIR_DD_UN_JUL:	; ------ NO SE CUMPLÓ ------
    CPI     R16, 10				 ; 
    BRNE    NO_ROLLOVER_JUL			 ; Si no, salta a almacenar DD_UN sin rollover

    ; Rollover: DD_UN llegó a 10
    CLR     R16					 ; R16 = 0 (nuevo DD_UN)
    STS     DD_UN, R16			; Guarda DD_UN = 0
    MOV     SHOW_DISP0, R16		; Muestra 0 en el display de unidades de día
	
    INC     R3             
    MOV     SHOW_DISP1, R3		; Muestra DD_DEC en el display de decenas de día
    RJMP    EXIT_LOOP


NO_ROLLOVER_JUL:
    ; Si DD_UN < 10, simplemente almacena el valor y lo muestra
    STS     DD_UN, R16
    MOV     SHOW_DISP0, R16
    MOV     SHOW_DISP1, R3
	MOV		SHOW_DISP2, R4
	MOV		SHOW_DISP3, R5

	RJMP	EXIT_LOOP

; -----------------------------------------------------------------------------
; ------------------------- AGOSTO ----------------------------
; -----------------------------------------------------------------------------

AGOSTO:
	LDI		R16, 0X08
	MOV		R4, R16
	MOV		SHOW_DISP2, R4
	CLR		R5
	MOV		SHOW_DISP3, R5

	; Manejo de DD_UN:
    LDS     R16, DD_UN			; R16 ? DD_UN
	CPI		R16, 0X02			; Comparar UNIDADES con 2 
	BRNE	SEGUIR_DD_UN_AGO	
	LDI		R16, 0X03		
	CP		R3, R16				; Comparar DECENAS con 3
	BREQ	IR_SEP				; Si ambas se cumplen, ir a SEPTIEMBRE
	LDS     R16, DD_UN			; Recuperar valor de DD_UN (si no se cumplió)
	RJMP	SEGUIR_DD_UN_AGO

IR_SEP:		; ------ SE CUMPLÓ QUE 08/31 ------
	LDI		R16, 0X01		
	STS		DD_UN, R16			; Cargar el valor para 1 de AGOSTO
	MOV		SHOW_DISP0, R16	
	CLR		R3					; Reiniciar DECENAS 
	MOV     SHOW_DISP1, R3	
	RJMP	SEPTIEMBRE					; IR A SEPTIEMBRE

SEGUIR_DD_UN_AGO:	; ------ NO SE CUMPLÓ ------
    CPI     R16, 10				 ; 
    BRNE    NO_ROLLOVER_AGO			 ; Si no, salta a almacenar DD_UN sin rollover

    ; Rollover: DD_UN llegó a 10
    CLR     R16					 ; R16 = 0 (nuevo DD_UN)
    STS     DD_UN, R16			; Guarda DD_UN = 0
    MOV     SHOW_DISP0, R16		; Muestra 0 en el display de unidades de día
	
    INC     R3             
    MOV     SHOW_DISP1, R3		; Muestra DD_DEC en el display de decenas de día
    RJMP    EXIT_LOOP


NO_ROLLOVER_AGO:
    ; Si DD_UN < 10, simplemente almacena el valor y lo muestra
    STS     DD_UN, R16
    MOV     SHOW_DISP0, R16
    MOV     SHOW_DISP1, R3
	MOV		SHOW_DISP2, R4
	MOV		SHOW_DISP3, R5

	RJMP	EXIT_LOOP

; -----------------------------------------------------------------------------
; ------------------------- SEPTIEMBRE ----------------------------
; -----------------------------------------------------------------------------

SEPTIEMBRE:

	LDI		R16, 0X09
	MOV		R4, R16
	MOV		SHOW_DISP2, R4
	CLR		R5
	MOV		SHOW_DISP3, R5

	; Manejo de DD_UN:
    LDS     R16, DD_UN			; R16 ? DD_UN
	CPI		R16, 0X01			; Comparar UNIDADES con 1
	BRNE	SEGUIR_DD_UN_SEP	
	LDI		R16, 0X03		
	CP		R3, R16				; Comparar DECENAS con 3
	BREQ	IR_OCT				; Si ambas se cumplen, ir a OCTUBRE
	LDS     R16, DD_UN			; Recuperar valor de DD_UN (si no se cumplió)
	RJMP	SEGUIR_DD_UN_SEP

IR_OCT:		; ------ SE CUMPLÓ QUE 09/30 ------
	LDI		R16, 0X01		
	STS		DD_UN, R16			; Cargar el valor para 1 de OCTUBRE
	MOV		SHOW_DISP0, R16	
	CLR		R3					; Reiniciar DECENAS 
	MOV     SHOW_DISP1, R3	
	RJMP	OCTUBRE				; IR A	OCTUBRE

SEGUIR_DD_UN_SEP:	; ------ NO SE CUMPLÓ ------
    CPI     R16, 10				 
    BRNE    NO_ROLLOVER_SEP	

    ; Rollover: DD_UN llegó a 10
    CLR     R16					 ; R16 = 0 (nuevo DD_UN)
    STS     DD_UN, R16			; Guarda DD_UN = 0
    MOV     SHOW_DISP0, R16		; Muestra 0 en el display de unidades de día
	
    INC     R3             
    MOV     SHOW_DISP1, R3		; Muestra DD_DEC en el display de decenas de día
    RJMP    EXIT_LOOP


NO_ROLLOVER_SEP:
    ; Si DD_UN < 10, simplemente almacena el valor y lo muestra
    STS     DD_UN, R16
    MOV     SHOW_DISP0, R16
    MOV     SHOW_DISP1, R3
	MOV		SHOW_DISP2, R4
	MOV		SHOW_DISP3, R5

	RJMP	EXIT_LOOP

; -----------------------------------------------------------------------------
; ------------------------- OCTUBRE ----------------------------
; -----------------------------------------------------------------------------

OCTUBRE:
	LDI		R16, 0X00
	MOV		R4, R16
	MOV		SHOW_DISP2, R4
	LDI		R16, 0X01
	MOV		R5, R16
	MOV		SHOW_DISP3, R5

	; Manejo de DD_UN:
    LDS     R16, DD_UN			; R16 ? DD_UN
	CPI		R16, 0X02			; Comparar UNIDADES con 2 
	BRNE	SEGUIR_DD_UN_OCT	
	LDI		R16, 0X03		
	CP		R3, R16				; Comparar DECENAS con 3
	BREQ	IR_NOV				; Si ambas se cumplen, ir a NOV
	LDS     R16, DD_UN			; Recuperar valor de DD_UN (si no se cumplió)
	RJMP	SEGUIR_DD_UN_OCT

IR_NOV:		; ------ SE CUMPLÓ QUE 10/31 ------
	LDI		R16, 0X01		
	STS		DD_UN, R16			; Cargar el valor para 1 de NOVIEMBRE
	MOV		SHOW_DISP0, R16	
	CLR		R3					; Reiniciar DECENAS 
	MOV     SHOW_DISP1, R3	
	RJMP	NOVIEMBRE			; IR A NOVIEMBRE

SEGUIR_DD_UN_OCT:	; ------ NO SE CUMPLÓ ------
    CPI     R16, 10				  
    BRNE    NO_ROLLOVER_OCT			

    ; Rollover: DD_UN llegó a 10
    CLR     R16					; R16 = 0 (nuevo DD_UN)
    STS     DD_UN, R16			; Guarda DD_UN = 0
    MOV     SHOW_DISP0, R16		; Muestra 0 en el display de unidades de día
	
    INC     R3             
    MOV     SHOW_DISP1, R3		; Muestra DD_DEC en el display de decenas de día
    RJMP    EXIT_LOOP


NO_ROLLOVER_OCT:
    ; Si DD_UN < 10, simplemente almacena el valor y lo muestra
    STS     DD_UN, R16
    MOV     SHOW_DISP0, R16
    MOV     SHOW_DISP1, R3
	MOV		SHOW_DISP2, R4
	MOV		SHOW_DISP3, R5

	RJMP	EXIT_LOOP

; -----------------------------------------------------------------------------
; ------------------------- NOVIEMBRE ----------------------------
; -------------------------------------------------------------------------

NOVIEMBRE:

	LDI		R16, 0X01
	MOV		R4, R16
	MOV		SHOW_DISP2, R4
	LDI		R16, 0X01
	MOV		R5, R16
	MOV		SHOW_DISP3, R5

	; Manejo de DD_UN:
    LDS     R16, DD_UN			; R16 ? DD_UN
	CPI		R16, 0X01			; Comparar UNIDADES con 1
	BRNE	SEGUIR_DD_UN_NOV	
	LDI		R16, 0X03		
	CP		R3, R16				; Comparar DECENAS con 3
	BREQ	IR_DIC				; Si ambas se cumplen, ir a DIC
	LDS     R16, DD_UN			; Recuperar valor de DD_UN (si no se cumplió)
	RJMP	SEGUIR_DD_UN_NOV

IR_DIC:		; ------ SE CUMPLÓ QUE 11/30 ------
	LDI		R16, 0X01		
	STS		DD_UN, R16			; Cargar el valor para 1 de DICIEMBRE
	MOV		SHOW_DISP0, R16	
	CLR		R3					; Reiniciar DECENAS 
	MOV     SHOW_DISP1, R3	
	RJMP	DICIEMBRE			; IR A DICIEMBRE

SEGUIR_DD_UN_NOV:	; ------ NO SE CUMPLÓ ------
    CPI     R16, 10				 ; 
    BRNE    NO_ROLLOVER_NOV		 ; Si no, salta a almacenar DD_UN sin rollover

    ; Rollover: DD_UN llegó a 10
    CLR     R16					; R16 = 0 (nuevo DD_UN)
    STS     DD_UN, R16			; Guarda DD_UN = 0
    MOV     SHOW_DISP0, R16		; Muestra 0 en el display de unidades de día
	
    INC     R3             
    MOV     SHOW_DISP1, R3		; Muestra DD_DEC en el display de decenas de día
    RJMP    EXIT_LOOP


NO_ROLLOVER_NOV:
    ; Si DD_UN < 10, simplemente almacena el valor y lo muestra
    STS     DD_UN, R16
    MOV     SHOW_DISP0, R16
    MOV     SHOW_DISP1, R3
	MOV		SHOW_DISP2, R4
	MOV		SHOW_DISP3, R5

	RJMP	EXIT_LOOP

; -----------------------------------------------------------------------------
; ------------------------- DICIEMBRE ----------------------------
; -------------------------------------------------------------------------
DICIEMBRE:

	LDI		R16, 0X02
	MOV		R4, R16
	MOV		SHOW_DISP2, R4
	LDI		R16, 0X01
	MOV		R5, R16
	MOV		SHOW_DISP3, R5

	; Manejo de DD_UN:
    LDS     R16, DD_UN			; R16 ? DD_UN
	CPI		R16, 0X02			; Comparar UNIDADES con 2 
	BRNE	SEGUIR_DD_UN_DIC	
	LDI		R16, 0X03		
	CP		R3, R16				; Comparar DECENAS con 3
	BREQ	IR_NEW_YEAR			; Si ambas se cumplen, ir a ENERO
	LDS     R16, DD_UN			; Recuperar valor de DD_UN (si no se cumplió)
	RJMP	SEGUIR_DD_UN_DIC

IR_NEW_YEAR:		; ------ SE CUMPLÓ QUE 12/31 ------
	LDI		R16, 0X01		
	STS		DD_UN, R16			; Cargar el valor para 1 de ENERO
	MOV		SHOW_DISP0, R16	
	CLR		R3					; Reiniciar DECENAS 
	MOV     SHOW_DISP1, R3	
	RJMP	NEW_YEAR			; IR A AÑO NUEVO

SEGUIR_DD_UN_DIC:	; ------ NO SE CUMPLÓ ------
    CPI     R16, 10				  
    BRNE    NO_ROLLOVER_DIC	

    ; Rollover: DD_UN llegó a 10
    CLR     R16					; R16 = 0 (nuevo DD_UN)
    STS     DD_UN, R16			; Guarda DD_UN = 0
    MOV     SHOW_DISP0, R16		; Muestra 0 en el display de unidades de día
	
    INC     R3             
    MOV     SHOW_DISP1, R3		; Muestra DD_DEC en el display de decenas de día
    RJMP    EXIT_LOOP

NO_ROLLOVER_DIC:
    ; Si DD_UN < 10, simplemente almacena el valor y lo muestra
    STS     DD_UN, R16
    MOV     SHOW_DISP0, R16
    MOV     SHOW_DISP1, R3
	MOV		SHOW_DISP2, R4
	MOV		SHOW_DISP3, R5

	RJMP	EXIT_LOOP

; -----------------------------------------------------------------------------
; ------------------------- AÑO NUEVO ----------------------------
; -------------------------------------------------------------------------

NEW_YEAR:	
	LDI		R16, 0X00
	MOV		R4, R16 
	MOV		R5, R16

	JMP		EXIT_LOOP
	


; =============================================================================
; ========================== CONFIGURAR HORA ===========================
; =============================================================================

CONFIGURAR_HORA:

	CPI		FLAG, 2
	BRNE	IR_CONFIGURAR_FECHA
	SBI		PORTD, 7
	SBI		PORTC, 0				; Encender LED indicador 
	CBI		PORTC, 1
	CBI		PORTB, 5
	RJMP	SEGUIR_CONF_HORA

IR_CONFIGURAR_FECHA:
	RJMP	CONFIGURAR_FECHA

	; Extraer nuevos valores de la hora y mostrarlo en los display
SEGUIR_CONF_HORA:	
	MOV		SHOW_DISP0, MIN_UN
	MOV		SHOW_DISP1, MIN_DEC
	MOV		SHOW_DISP2, HORA_UN
	MOV		SHOW_DISP3, HORA_DEC

	RJMP	EXIT_LOOP


; =============================================================================
; ========================== CONFIGURAR FECHA ===========================
; =============================================================================

CONFIGURAR_FECHA:
	CPI		FLAG, 3
	BRNE	IR_CONFIGURAR_ALARMA
	RJMP	STAY_CONFIGURAR_FECHA

IR_CONFIGURAR_ALARMA:
	RJMP	CONFIGURAR_ALARMA

STAY_CONFIGURAR_FECHA:

	SBI		PORTD, 7
	CBI		PORTC, 0 
	SBI		PORTC, 1				; Encender LED indicador
	CBI		PORTB, 5

	LDS		R16, DD_UN 
	CPI		R16, 0X00
	BRNE	SHOW_DISP				; Si el día = 0, cargar valor
	CP		R4, R16 
	BREQ	CARGAR_MES	
	RJMP	SHOW_DISP

CARGAR_MES:
	LDI		R16, 0X01				; cargar 1 para iniciar calendario
	STS		DD_UN, R16
	RJMP	SHOW_DISP

; extraer el nuevo valor del calendario y mostrar un displays
SHOW_DISP:
	LDS		R16, DD_UN 
	MOV		SHOW_DISP0,	R16 
	MOV		SHOW_DISP1, R3
	MOV		SHOW_DISP2, R4 
	MOV		SHOW_DISP3, R5

	RJMP	EXIT_LOOP


; =============================================================================
; ========================== CONFIGURAR ALARMA ===========================
; =============================================================================

CONFIGURAR_ALARMA:

	CPI		FLAG, 4
	BRNE	EXIT_LOOP
	SBI		PORTD, 7
	SBI		PORTC, 0				;Encender LED indicador
	SBI		PORTC, 1				;Encender LED indicador
	CBI		PORTB, 5

	; exraer el valor de la alarma y mostrar en displays
	MOV		SHOW_DISP0, MIN_UN_ALARMA
	MOV		SHOW_DISP1, MIN_DEC_ALARMA
	MOV		SHOW_DISP2, HORA_UN_ALARMA
	MOV		SHOW_DISP3, HORA_DEC_ALARMA




EXIT_LOOP:

	RJMP	LOOP




; =============================================================================
; ========================== PINCHANGE INTERRUPCION ===========================
; =============================================================================
ISR_PCINT0:

	PUSH    R16
    IN      R16, SREG
    PUSH    R16

    ; PB0 se lee siempre, sin importar FLAG.
    SBIS    PINB, 0
    RJMP    HANDLE_PB0


; -----------------------------------------------------------------------------
; ------------------------- LEER BANDERAS ----------------------------
; -------------------------------------------------------------------------


    ; Solo se verifican PB1 a PB4 si FLAG es 2 o 4.
	CPI		FLAG, 0
	BREQ	IR_PCINT0_EXIT

	CPI		FLAG, 1
	BREQ	IR_PCINT0_EXIT

    CPI     FLAG, 2
    BREQ    VERIFY_PB_HORA	 
	
	CPI		FLAG, 3
	BREQ	GO_VERIFY_PB_FECHA   

    CPI     FLAG, 4
    BREQ    GO_VERIFY_PB_ALARMA


    RJMP    PCINT0_EXIT		

GO_VERIFY_PB_FECHA:
	RJMP	VERIFY_PB_FECHA
	
GO_VERIFY_PB_ALARMA:
	RJMP	VERIFY_PB_ALARMA    


; -----------------------------------------------------------------------------
; ------------------------- RUTINA PARA CONFIGURAR HORA ----------------------------
; -------------------------------------------------------------------------


; ------------------------- VERIFCAR BOTON ----------------------------

VERIFY_PB_HORA:
    ; Verifica si PB1 está en LOW
    SBIS    PINB, 1
    RJMP    HANDLE_PB1

    ; Verifica si PB2 está en LOW
    SBIS    PINB, 2
    RJMP    HANDLE_PB2

    ; Verifica si PB3 está en LOW
    SBIS    PINB, 3
    RJMP    HANDLE_PB3

    ; Verifica si PB4 está en LOW
    SBIS    PINB, 4
    RJMP    HANDLE_PB4

    RJMP    PCINT0_EXIT

; ------------------------- PB0 INCREMENTA FLAG ----------------------------


HANDLE_PB0:
    ; Acción para PB0: Incrementa FLAG
    INC     FLAG
    CPI     FLAG, 5
    BRNE    IR_PCINT0_EXIT
    CLR     FLAG				; Regresa a 0 cuando llegue a 5
    RJMP    IR_PCINT0_EXIT

IR_PCINT0_EXIT:
	RJMP	PCINT0_EXIT


; ------------------------- PB1 INCREMENTA HORA ----------------------------


HANDLE_PB1:
	INC		HORA_UN						; Incrementa Unidad de hora
	CPI		HORA_DEC, 0X02				; Si la decenas es 2
	BRNE	SEGUIR_CONF
	CPI		HORA_UN, 0X04				; Si la unidad es 4
	BRNE	SEGUIR_CONF

	; Si ya son las 23h
	CLR		HORA_UN						; REINICIA RELOJ (OVERFLOW)
	CLR		HORA_DEC					; REINICIA RELOJ (OVERFLOW)
	MOV		SHOW_DISP2, HORA_UN 
	MOV		SHOW_DISP3, HORA_DEC

SEGUIR_CONF:
	CPI		HORA_UN, 0X0A				; Comparar con 10
	BREQ	INCREMENTAR_HORA_DEC		; Si es 10, saltar a INCREMENTAR DECENA DE HORA
	MOV		SHOW_DISP2, HORA_UN			; Si no es 10, mostrar en display
	RJMP	PCINT0_EXIT
		
INCREMENTAR_HORA_DEC:
	CLR		HORA_UN						; Reiniciar unidades 
	MOV		SHOW_DISP2, HORA_UN			; mostrar unidades 
	
	INC		HORA_DEC					; incrmentar decena
	MOV		SHOW_DISP3, HORA_DEC		; mostrar en display
	RJMP	PCINT0_EXIT
   

; ------------------------- PB2 DECREMENTA HORA ----------------------------


HANDLE_PB2:
	DEC		HORA_UN						; decrementar unidad de hora
	CPI		HORA_DEC, 0X00				; Si la decena es = 0 
	BRNE	SEGUIR_DECREMENTO
	CPI		HORA_UN, 0XFF				; si la unidad es = -1
	BRNE	SEGUIR_DECREMENTO

	; Si ya son las 00h (caso de 00 -> 23)
	LDI		HORA_UN, 0X03				; cargar 3 en unidad
	LDI		HORA_DEC, 0X02				; cargar 2 en decena
	MOV		SHOW_DISP2, HORA_UN			; mostar en display
	MOV		SHOW_DISP3, HORA_DEC		; mostrar en display
	RJMP	PCINT0_EXIT   ; Salto para evitar seguir al bloque SEGUIR_DECREMENTO

SEGUIR_DECREMENTO:		
	CPI		HORA_UN, 0XFF				; si la unidad = -1
	BREQ	UNDERFLOW2					; hubo underflow
	MOV		SHOW_DISP2, HORA_UN
	RJMP	PCINT0_EXIT

UNDERFLOW2:
	LDI		HORA_UN, 0X09				; cargar en la unidad 09 (caso de 10 -> 09)
	MOV		SHOW_DISP2, HORA_UN			; mostrar en display
	DEC		HORA_DEC					; decrementar decenas
	MOV		SHOW_DISP3, HORA_DEC		; mostrar en display
	RJMP	PCINT0_EXIT	
	
; ------------------------- PB3 INCREMENTA MINUTOS ----------------------------

HANDLE_PB3:
	INC     MIN_UN						; Incrementar unidad de minuto
    CPI     MIN_UN, 0x0A				; comparar si = 10
    BREQ    INCREMENTAR_MIN_DEC			
    MOV     SHOW_DISP0, MIN_UN	;Carga a puntero 
    RJMP    PCINT0_EXIT

INCREMENTAR_MIN_DEC:
	CLR		MIN_UN						; rst unidades
	MOV		SHOW_DISP0, MIN_UN			; mostrar 

	INC		MIN_DEC						; aumentar decenas de minuto
	CPI		MIN_DEC, 0X06				; si ya llego = 6 (60 minutos)
	BREQ	RST_MIN_DEC			
	MOV		SHOW_DISP1, MIN_DEC			; si no, mostrar 
	RJMP	PCINT0_EXIT

RST_MIN_DEC:
	CLR		MIN_DEC						; resetear decenenas
	MOV		SHOW_DISP1, MIN_DEC			; mostrar
	RJMP	PCINT0_EXIT
	

; ------------------------- PB4 DECREMENTA MINUTOS ----------------------------

HANDLE_PB4:
	DEC     MIN_UN						; decrementar minutos
    CPI     MIN_UN, 0xFF				; si = -1
    BREQ    UNDERFLOW	
    MOV     SHOW_DISP0, MIN_UN	;		Carga a puntero 
    RJMP    PCINT0_EXIT		

UNDERFLOW:
	LDI		MIN_UN, 0X09				; cargar 0x09
	MOV		SHOW_DISP0, MIN_UN

	DEC		MIN_DEC						; decrementar decena de minuto
	CPI		MIN_DEC, 0XFF				;comparar si = -1
	BREQ	UNDERFLOW1
	MOV		SHOW_DISP1, MIN_DEC			; mostrar
	RJMP	PCINT0_EXIT

UNDERFLOW1:	
	LDI		MIN_DEC, 0X05				; cargar 5 (59)
	MOV		SHOW_DISP1, MIN_DEC			;mostrar
	RJMP	PCINT0_EXIT
	

; -----------------------------------------------------------------------------
; ------------------------- RUTINA DE CONFIGURAR ALARMA ----------------------------
; -------------------------------------------------------------------------

; ------------------------- VERIFICA BOTON ----------------------------


VERIFY_PB_ALARMA:
    ; Verifica si PB1 está en LOW
    SBIS    PINB, 1
    RJMP    HANDLE_PB1_ALARMA

    ; Verifica si PB2 está en LOW
    SBIS    PINB, 2
    RJMP    HANDLE_PB2_ALARMA

    ; Verifica si PB3 está en LOW
    SBIS    PINB, 3
    RJMP    HANDLE_PB3_ALARMA

    ; Verifica si PB4 está en LOW
    SBIS    PINB, 4
    RJMP    HANDLE_PB4_ALARMA

    RJMP    PCINT0_EXIT


; ------------------------- PB1 ESTABLECE HORA ----------------------------

;<<<< ESTA RUTINA FUNCIONA EXACTAMENTE IGUAL QUE LA DE CONFIGURAR HORA, SOLO CAMBIAN LOS REGISTROS >>>>

HANDLE_PB1_ALARMA:
	INC		HORA_UN_ALARMA				
	LDI		R16, 0X02
	CP		HORA_DEC_ALARMA, R16
	BRNE	SEGUIR_CONF_ALARMA
	LDI		R16, 0X04
	CP		HORA_UN_ALARMA, R16
	BRNE	SEGUIR_CONF_ALARMA

	; Si ya son las 23h
	CLR		HORA_UN_ALARMA 
	CLR		HORA_DEC_ALARMA
	MOV		SHOW_DISP2, HORA_UN_ALARMA 
	MOV		SHOW_DISP3, HORA_DEC_ALARMA

SEGUIR_CONF_ALARMA:
	LDI		R16, 0X0A
	CP		HORA_UN_ALARMA, R16
	BREQ	INCREMENTAR_HORA_DEC_ALARMA
	MOV		SHOW_DISP2, HORA_UN_ALARMA
	RJMP	PCINT0_EXIT

INCREMENTAR_HORA_DEC_ALARMA:
	CLR		HORA_UN_ALARMA
	MOV		SHOW_DISP2, HORA_UN_ALARMA
	
	INC		HORA_DEC_ALARMA
	MOV		SHOW_DISP3, HORA_DEC_ALARMA 
	RJMP	PCINT0_EXIT
    


; ------------------------- PB2 ESTABLECE HORA ---------------------------

HANDLE_PB2_ALARMA:
	DEC		HORA_UN_ALARMA
	CLR		R16
	CP		HORA_DEC_ALARMA, R16
	BRNE	SEGUIR_DECREMENTO_ALARMA
	LDI		R16, 0XFF
	CP		HORA_UN_ALARMA, R16
	BRNE	SEGUIR_DECREMENTO_ALARMA

	; Si ya son las 23h (caso de 00 -> 23)
	LDI		R16, 0X03
	MOV		HORA_UN_ALARMA, R16
	LDI		R16, 0X02
	MOV		HORA_DEC_ALARMA, R16
	MOV		SHOW_DISP2, HORA_UN_ALARMA 
	MOV		SHOW_DISP3, HORA_DEC_ALARMA
	RJMP	PCINT0_EXIT   ; Salto para evitar seguir al bloque SEGUIR_DECREMENTO

SEGUIR_DECREMENTO_ALARMA:
	LDI		R16, 0XFF
	CP		HORA_UN_ALARMA, R16
	BREQ	UNDERFLOW2_ALARMA
	MOV		SHOW_DISP2, HORA_UN_ALARMA
	RJMP	PCINT0_EXIT

UNDERFLOW2_ALARMA:
	LDI		R16, 0X09
	MOV		HORA_UN_ALARMA, R16
	MOV		SHOW_DISP2, HORA_UN_ALARMA
	DEC		HORA_DEC_ALARMA
	MOV		SHOW_DISP3, HORA_DEC_ALARMA
	RJMP	PCINT0_EXIT
	
	

; ------------------------- PB3 ESTABLECE HORA ---------------------------


HANDLE_PB3_ALARMA:
	INC     MIN_UN_ALARMA
	LDI		R16, 0X0A
    CP		MIN_UN_ALARMA, R16		
    BREQ    INCREMENTAR_MIN_DEC_ALARMA	
    MOV     SHOW_DISP0, MIN_UN_ALARMA	;Carga a puntero 
    RJMP    PCINT0_EXIT

INCREMENTAR_MIN_DEC_ALARMA:
	CLR		MIN_UN_ALARMA
	MOV		SHOW_DISP0, MIN_UN_ALARMA

	INC		MIN_DEC_ALARMA
	LDI		R16, 0X06
	CP		MIN_DEC_ALARMA, R16
	BREQ	RST_MIN_DEC_ALARMA
	MOV		SHOW_DISP1, MIN_DEC_ALARMA
	RJMP	PCINT0_EXIT

RST_MIN_DEC_ALARMA:
	CLR		MIN_DEC_ALARMA
	MOV		SHOW_DISP1, MIN_DEC_ALARMA
	RJMP	PCINT0_EXIT

	
; ------------------------- PB4 ESTABLECE HORA ---------------------------


HANDLE_PB4_ALARMA:
	DEC     MIN_UN_ALARMA
	LDI		R16, 0XFF
    CP	    MIN_UN_ALARMA, R16	
    BREQ    UNDERFLOW_ALARMA	
    MOV     SHOW_DISP0, MIN_UN_ALARMA	;Carga a puntero 
    RJMP    PCINT0_EXIT

UNDERFLOW_ALARMA:
	LDI		R16, 0X09
	MOV		MIN_UN_ALARMA, R16
	MOV		SHOW_DISP0, MIN_UN_ALARMA

	DEC		MIN_DEC_ALARMA
	LDI		R16, 0XFF
	CP		MIN_DEC_ALARMA, R16
	BREQ	UNDERFLOW1_ALARMA
	MOV		SHOW_DISP1, MIN_DEC_ALARMA
	RJMP	PCINT0_EXIT

UNDERFLOW1_ALARMA:
	LDI		R16, 0X05
	MOV		MIN_DEC_ALARMA, R16
	MOV		SHOW_DISP1, MIN_DEC_ALARMA
	RJMP	PCINT0_EXIT


; -----------------------------------------------------------------------------
; ------------------------- RUTINA DE CONFIGUARCION ALARMA ----------------------------
; -------------------------------------------------------------------------

; ------------------------- Verificar boton ----------------------------


VERIFY_PB_FECHA:
	; Verifica si PB1 está en LOW
    SBIS    PINB, 1
    RJMP    HANDLE_PB1_FECHA

    ; Verifica si PB2 está en LOW
    SBIS    PINB, 2
    RJMP    HANDLE_PB2_FECHA

    ; Verifica si PB3 está en LOW
    SBIS    PINB, 3
    RJMP    HANDLE_PB3_FECHA

    ; Verifica si PB4 está en LOW
    SBIS    PINB, 4
    RJMP    HANDLE_PB4_FECHA

    RJMP    PCINT0_EXIT


; ------------------------- PB1 INCREMENTA MES ---------------------------

HANDLE_PB1_FECHA: 

	LDI		R16, 0X01			; Verificar si la decena de mes = 1
	CP		R5, R16 
	BRNE	INCREMENTAR_MM_UN	
	LDI		R16, 0X02
	CP		R4,	R16				; verificar si la unidad de mes = 2 (mes 12)
	BRNE	INCREMENTAR_MM_UN
			
	LDI		R16, 0X01			; SI SE CUMPLE, regresar a enero (UNIDAD = 1)
	MOV		R4, R16
	MOV		SHOW_DISP2, R4 
	CLR		R5					; decena = 9
	MOV		SHOW_DISP3, R5
	RJMP	PCINT0_EXIT
	
INCREMENTAR_MM_UN:
	INC		R4					; SI NO SE CUMPLE (mes 12) 
	LDI		R16, 0X0A			; comparar con 10 
	CP		R4, R16 
	BREQ	OVERFLOW_MM_UN
	MOV		SHOW_DISP2, R4		; mostrar 
	RJMP	PCINT0_EXIT

OVERFLOW_MM_UN:
	CLR		R4					; rst unidades de mes
	MOV		SHOW_DISP2, R4	
	INC		R5					; incrmentar decenas 
	LDI		R16, 0X02			; si ya llego a 2 
	CP		R5, R16 
	BREQ	OVERFLOW_MM_DEC	
	MOV		SHOW_DISP3, R5		; si no, mostrar
	RJMP	PCINT0_EXIT

OVERFLOW_MM_DEC:
	CLR		R5					; borrarlo 
	MOV		SHOW_DISP3, R5
	RJMP	PCINT0_EXIT


; ------------------------- PB2 DECREMENTA MES ---------------------------


HANDLE_PB2_FECHA:
	LDI		R16, 0X00				; verificar si la decena = 0 
	CP		R5, R16 
	BRNE	DECREMENTAR_MM_UN 
	LDI		R16, 0X01
	CP		R4,	R16					; verificar si la unidad = 1 (mes 01)
	BRNE	DECREMENTAR_MM_UN

	LDI		R16, 0X02				; SI SE CUMPLE, cargar 12 (UNDERFLOW)
	MOV		R4, R16
	MOV		SHOW_DISP2, R4 
	LDI		R16, 0X01
	MOV		R5, R16
	MOV		SHOW_DISP3, R5
	RJMP	PCINT0_EXIT
	
DECREMENTAR_MM_UN:		
	LDI		R16, 0X01				; SI NO SE CUMPLE, verificar si la decena = 1
	CP		R5, R16 
	BRNE	SEGUIR_DECREMENTANDO
	DEC		R4						; decrementar unidad 
	LDI		R16, 0XFF				; comparar unidad = -1
	CP		R4, R16
	BREQ	UNDERF
	MOV		SHOW_DISP2, R4		
	RJMP	PCINT0_EXIT

UNDERF:
	LDI		R16, 0X00				; cargar 0 en decena ( CASO 10 -> 09 )
	MOV		R5, R16
	LDI		R16, 0X09				; cargar 9 en unidad
	MOV		R4, R16
	MOV		SHOW_DISP2, R4
	MOV		SHOW_DISP3, R5
	RJMP	PCINT0_EXIT

SEGUIR_DECREMENTANDO:
	DEC		R4						; decrementar la unidad
	LDI		R16, 0X00				
	CP		R4, R16					; verificar si es cero
	BREQ	UNDERFLOW_MM_UN
	MOV		SHOW_DISP2, R4			; si no, mostrar
	RJMP	PCINT0_EXIT

UNDERFLOW_MM_UN:
	LDI		R16, 0X09				; si unidad = 0, cargar 9 (underflow)
	MOV		R4, R16					; mostrar
	MOV		SHOW_DISP2, R4
	DEC		R5						; decrementar decenas 
	LDI		R16, 0XFF	
	CP		R5, R16					; verificar underflow
	BREQ	UNDERFLOW_DD_DEC
	MOV		SHOW_DISP3, R5			; si no hubo, mostrar
	RJMP	PCINT0_EXIT

UNDERFLOW_DD_DEC:
	LDI		R16, 0X01				; si hubo, cargar nuevo valor
	MOV		SHOW_DISP3, R5
	RJMP	PCINT0_EXIT


; ------------------------- PB3 INCREMENTA DIA ---------------------------

HANDLE_PB3_FECHA:

; Revisa qué mes
	LDI		R16, 0X01
	CP		R5, R16
	BREQ	ULTIMO_TRIMESTRE		; ¿ Esta entre octubre y diciembre?
	LDI		R16, 0X00
	CP		R5, R16					; ¿ Esta entre enero y septiembre?
	BREQ	TRES_TRIMESTRES	
	RJMP	PCINT0_EXIT

	; Si está entre octubre y diciembre
ULTIMO_TRIMESTRE:
	LDI		R16, 0X00 
	CP		R4, R14 
	BREQ	MES_LARGO			; si es octubre 
	
	LDI		R16, 0X01			
	CP		R4, R16 
	BREQ	GO_MES_CORTO		; si es noviembre
	RJMP	DICIEMBRE_

GO_MES_CORTO:
	RJMP	MES_CORTO			

DICIEMBRE_:
	LDI		R16, 0X02
	CP		R4, R16 
	BREQ	MES_LARGO			; si es diciembre 

	RJMP	PCINT0_EXIT


TRES_TRIMESTRES:
	LDI		R16, 0X01			
	CP		R4, R16 
	BREQ	MES_LARGO			; Si es enero

	LDI		R16, 0X02 
	CP		R4, R16 
	BREQ	SOLO0_FEBRERO 
	RJMP	HOLAA

SOLO0_FEBRERO
	RJMP	SOLO_FEBRERO		; Si es febrero

HOLAA:
	LDI		R16, 0X03 
	CP		R4, R16	
	BREQ	MES_LARGO			; si es marzo

	LDI		R16, 0X04 
	CP		R4, R16		
	BREQ	MES_CORTO			; si es abril

	LDI		R16, 0X05 
	CP		R4, R16 
	BREQ	MES_LARGO			; si es mayo
		
	LDI		R16, 0X06 
	CP		R4, R16 
	BREQ	MES_CORTO			; si es junio 

	LDI		R16, 0X07 
	CP		R4, R16 
	BREQ	MES_LARGO			; si es julio

	LDI		R16, 0X08 
	CP		R4, R16 
	BREQ	MES_LARGO			; si es agosto

	LDI		R16, 0X09 
	CP		R4, R16 
	BREQ	MES_CORTO			; si es septiembre
	
	RJMP	PCINT0_EXIT

MES_LARGO:
	LDS		R16, DD_UN 
	CPI		R16, 0X01				; Comparar si la unidad de dia = 1 
	BRNE	INCREMENTAR_DD_UN
	LDI		R16, 0X03				; Comparar si la decena de dia = 3
	CP		R3, R16 
	BRNE	INCREMENTAR_DD_UN
	

	LDI		R16, 0X01				; SI YA ES 31 , resetear
	STS		DD_UN, R16 
	MOV		SHOW_DISP0, R16 
	CLR		R3						; cargar día 01
	MOV		SHOW_DISP0, R3
	RJMP	PCINT0_EXIT

INCREMENTAR_DD_UN:
	LDS		R16, DD_UN 
	INC		R16						; incrementar unidades
	CPI		R16, 0X0A				; comparar con 10
	BREQ	OVERFLOW_DD_UN
	STS		DD_UN, R16				; si no es 10, volver a guardar 
	MOV		SHOW_DISP0, R16
	RJMP	PCINT0_EXIT 

OVERFLOW_DD_UN:
	CLR		R16						; si es 10, resetear (overflow)
	STS		DD_UN, R16 
	MOV		SHOW_DISP0, R16			; mostrar unidades
	INC		R3						; incrementar decenas

	MOV		SHOW_DISP1, R3			; mostrar decenas
	RJMP	PCINT0_EXIT
	
MES_CORTO:

	LDS		R16, DD_UN 
	CPI		R16, 0X00				; verificar si la unidad = 0
	BRNE	INCREMENTAR_DD_UN_
	LDI		R16, 0X03 
	CP		R3, R16					; verificar si la decena = 3 (dia 30)
	BRNE	INCREMENTAR_DD_UN_
	

	LDI		R16, 0X01				; SI YA ES 30, hacer overflow
	STS		DD_UN, R16 
	MOV		SHOW_DISP0, R16 
	CLR		R3						; cargar día (01)
	MOV		SHOW_DISP0, R3
	RJMP	PCINT0_EXIT

INCREMENTAR_DD_UN_:
	LDS		R16, DD_UN 
	INC		R16						; incrementar unidades
	CPI		R16, 0X0A				; comparar con 10
	BREQ	OVERFLOW_DD_UN_
	STS		DD_UN, R16				; si no ha llegado , mostrar
	MOV		SHOW_DISP0, R16
	RJMP	PCINT0_EXIT 

OVERFLOW_DD_UN_:	
	CLR		R16						; si ya llego (overflow) resetear
	STS		DD_UN, R16 
	MOV		SHOW_DISP0, R16			; cargar valor en display
	INC		R3						; incrementar decenas

	MOV		SHOW_DISP1, R3			; cargar valor en display
	RJMP	PCINT0_EXIT

SOLO_FEBRERO:
	LDS		R16, DD_UN 
	CPI		R16, 0X08				; Si resulta que es febrero, comparar unidades = 8
	BRNE	_INCREMENTAR_DD_UN_
	LDI		R16, 0X02				; comparar decenas con 2 (dia 28)
	CP		R3, R16 
	BRNE	_INCREMENTAR_DD_UN_
	

	LDI		R16, 0X01				; Si se cumple (28)
	STS		DD_UN, R16 
	MOV		SHOW_DISP0, R16 
	CLR		R3						; cargar 01 (overflow)
	MOV		SHOW_DISP0, R3
	RJMP	PCINT0_EXIT

_INCREMENTAR_DD_UN_:
	LDS		R16, DD_UN				
	INC		R16						; incrementar unidades
	CPI		R16, 0X0A				; comparar con 10
	BREQ	_OVERFLOW_DD_UN_
	STS		DD_UN, R16				; no ha llegado a 10, mostrar
	MOV		SHOW_DISP0, R16
	RJMP	PCINT0_EXIT 

_OVERFLOW_DD_UN_:
	CLR		R16						; ya llego a 10, resetear 
	STS		DD_UN, R16 
	MOV		SHOW_DISP0, R16
	INC		R3						; incrmentar decenas 

	MOV		SHOW_DISP1, R3			; mostrar decenas
	RJMP	PCINT0_EXIT


; ------------------------- PB4 DECREMENTA DIA ---------------------------


HANDLE_PB4_FECHA:

	; Revisa qué mes
	LDI		R16, 0X01				; Revisar si estamos entre octubre y diciembre 
	CP		R5, R16
	BREQ	_ULTIMO_TRIMETRE
	LDI		R16, 0X00
	CP		R5, R16					; revisar si estamos entre septiembre y enero 
	BREQ	_TRES_TRIMESTRES
	RJMP	PCINT0_EXIT

; Estamos entre octubre y diciembre
_ULTIMO_TRIMETRE:
	LDI		R16, 0X00				; Verificar si es octubre
	CP		R4, R14 
	BREQ	_MES_LARGO				
	
	LDI		R16, 0X01				; Verificar si es noviembre
	CP		R4, R16 
	BREQ	IR_MES_CORTO 
	RJMP	_DICIEMBRE

IR_MES_CORTO:
	RJMP	_MES_CORTO

_DICIEMBRE:
	LDI		R16, 0X02				; Verificar si es diciembre
	CP		R4, R16 
	BREQ	_MES_LARGO

	RJMP	PCINT0_EXIT


_TRES_TRIMESTRES:
	LDI		R16, 0X01				; si es enero 
	CP		R4, R16 
	BREQ	_MES_LARGO 

	LDI		R16, 0X02 
	CP		R4, R16 
	BREQ	SOLOO_FEBRERO 
	RJMP	_HOLAA

SOLOO_FEBRERO:
	RJMP	_SOLO_FEBRERO			; si es febrero

_HOLAA:
	LDI		R16, 0X03 
	CP		R4, R16
	BREQ	_MES_LARGO				; si es marzo 

	LDI		R16, 0X04 
	CP		R4, R16 
	BREQ	_MES_CORTO				; si es abril

	LDI		R16, 0X05 
	CP		R4, R16 
	BREQ	_MES_LARGO				; si es mayo 

	LDI		R16, 0X06 
	CP		R4, R16 
	BREQ	_MES_CORTO				; si es junio 

	LDI		R16, 0X07 
	CP		R4, R16		
	BREQ	_MES_LARGO				; si es julio 

	LDI		R16, 0X08 
	CP		R4, R16 
	BREQ	_MES_LARGO				; si es agosto

	LDI		R16, 0X09 
	CP		R4, R16 
	BREQ	_MES_CORTO				; si es septiembre
	
	RJMP	PCINT0_EXIT

_MES_LARGO:

	LDS		R16, DD_UN 
	CPI		R16, 0X01				; comparar si la unidad es 1 
	BRNE	DECREMENTAR_DD_UN
	LDI		R16, 0X00					
	CP		R3, R16					; comparar si la decena es 0 ( 01 )
	BRNE	DECREMENTAR_DD_UN
	

	LDI		R16, 0X01				; SI SE CUMPLE QUE (01)
	STS		DD_UN, R16 
	MOV		SHOW_DISP0, R16 
	LDI		R16, 0X03				; cargar  dia 31 (underflow)
	MOV		R3, R16
	MOV		SHOW_DISP0, R3
	RJMP	PCINT0_EXIT
		
DECREMENTAR_DD_UN:					; Si aun no es 31 
	LDS		R16, DD_UN			
	DEC		R16						; decrementar unidades
	CPI		R16, 0XFF				; verificar si es -1
	BREQ	UNDERFLOW_DD_UN
	STS		DD_UN, R16				; si no lo es, mostrar 
	MOV		SHOW_DISP0, R16
	RJMP	PCINT0_EXIT 

UNDERFLOW_DD_UN:
	LDI		R16, 0X09				; si lo es, cargar 09 (underflow)
	STS		DD_UN, R16				
	MOV		SHOW_DISP0, R16			; mostrar unidades
	DEC		R3						; decrementar decenas
	MOV		SHOW_DISP1, R3			; mostrar decenas
	RJMP	PCINT0_EXIT
	
_MES_CORTO:

	LDS		R16, DD_UN 
	CPI		R16, 0X01				; verificar si la unidad  es 1
	BRNE	DECREMENTAR_DD_UN_		
	LDI		R16, 0X00 
	CP		R3, R16					; verificar si la decena es 0 ( 01 )
	BRNE	DECREMENTAR_DD_UN_
	

	LDI		R16, 0X00				; SI SE CUMPLE QUE (01)
	STS		DD_UN, R16	
	MOV		SHOW_DISP0, R16 
	LDI		R16, 0X03				; cargar 30 (UNDERFLOW)
	MOV		R3, R16
	MOV		SHOW_DISP0, R3
	RJMP	PCINT0_EXIT

DECREMENTAR_DD_UN_:
	LDS		R16, DD_UN				; si no se cumple
	DEC		R16 
	CPI		R16, 0XFF				; verificar si decenas = -1
	BREQ	UNDERFLOW_DD_UN_	
	STS		DD_UN, R16				; si no se cumple, mostrar
	MOV		SHOW_DISP0, R16
	RJMP	PCINT0_EXIT 

UNDERFLOW_DD_UN_:
	LDI		R16, 0X09				; Cargar 09 (underflow)
	STS		DD_UN, R16 
	MOV		SHOW_DISP0, R16			; mostrar unidades
	DEC		R3						; decrementar decenas 
	MOV		SHOW_DISP1, R3			; mostrar decenas
	RJMP	PCINT0_EXIT

_SOLO_FEBRERO:
	LDS		R16, DD_UN 
	CPI		R16, 0X01				; comparar unidades con 1
	BRNE	_DECREMENTAR_DD_UN_
	LDI		R16, 0X00 
	CP		R3, R16					; comparar decenas con 0 
	BRNE	_DECREMENTAR_DD_UN_
	

	LDI		R16, 0X08				; SI SE CUMPLE QUE (01)
	STS		DD_UN, R16 
	MOV		SHOW_DISP0, R16 
	LDI		R16, 0X02				; cargar 28 (undeflow) para febrero
	MOV		R3, R16
	MOV		SHOW_DISP0, R3
	RJMP	PCINT0_EXIT

_DECREMENTAR_DD_UN_:
	LDS		R16, DD_UN				; si no se cumple 
	DEC		R16						; decrementar unidades 
	CPI		R16, 0XFF				; verificar si ya es -1 
	BREQ	_UNDERFLOW_DD_UN_
	STS		DD_UN, R16				; mostar unidades
	MOV		SHOW_DISP0, R16
	RJMP	PCINT0_EXIT 

_UNDERFLOW_DD_UN_:
	LDI		R16, 0X09				; si ya se cumplio, cargar 09 
	STS		DD_UN, R16				
	MOV		SHOW_DISP0, R16			; mostrar unidades
	DEC		R3						; decrementar decenas
	MOV		SHOW_DISP1, R3			; mostrar decenas
	RJMP	PCINT0_EXIT


PCINT0_EXIT:
	POP     R16
    OUT     SREG, R16
    POP     R16
    RETI


; =============================================================================
; ========================== TIMER0 INTERRUPCION ===========================
; =============================================================================

ISR_TIMER0:
    ; --- Salvar registros usados ---
    PUSH    R16
    PUSH    R24            ; R24 lo usaremos como auxiliar
    IN      R16, SREG
    PUSH    R16

    ; --- Recargar Timer0 ---
    LDI     R16, VALOR_TMR0
    OUT     TCNT0, R16

; -----------------------------------------------------------------------------
; ------------------------- VERIFICAR FLAG ----------------------------
; -------------------------------------------------------------------------

	CPI		FLAG, 2				; Verifica flag MENOR a 2
	BRLO	TIME_CNT
	CPI		FLAG, 2
	BREQ	TIME_UPDATED1
	CPI		FLAG, 3
	BREQ	TIME_UPDATED1
	CPI		FLAG, 4
	BREQ	TIME_UPDATED1

; -----------------------------------------------------------------------------
; ------------------------- INCREMENTOS DE TIEMPO ----------------------------
; -------------------------------------------------------------------------

TIME_CNT:

    INC     OVCNT    
	CPI		OVCNT, 32        ; Cada overflow ~5ms
    BRNE    SKIP_TIME
    CLR     OVCNT

    INC     MIN_UN
	CPI		MIN_UN, 10
    BRNE    CHECK_FLAG0
    ; MIN_UN llegó a 10 => reset y sumar 1 a MIN_DEC
    CLR     MIN_UN
    INC     MIN_DEC
	CPI		MIN_DEC, 6
    BRNE    CHECK_FLAG0
    ; MIN_DEC llegó a 6 => reset y sumar 1 a HORA_UN
    CLR     MIN_DEC
	CPI		HORA_DEC, 2 
	BRNE	CONTINUAR 
	CPI		HORA_UN, 3 
	BRNE	CONTINUAR

	; --------- Pasó un día -------
	LDS		R16, DD_UN
	INC		R16 
	STS		DD_UN, R16

	CLR		HORA_UN
	CLR		HORA_DEC
	RJMP	CHECK_FLAG0

CONTINUAR:
	INC     HORA_UN
	CPI		HORA_UN, 10
    BRNE    CHECK_FLAG0
    ; HORA_UN llegó a 10
	CLR		HORA_UN
	INC		HORA_DEC
    RJMP    CHECK_FLAG0

; -----------------------------------------------------------------------------
; ------------------------- VERIFICAR BANDERA  ----------------------------
; -------------------------------------------------------------------------

CHECK_FLAG0:
	CPI		FLAG, 0
	BRNE	CHECK_FLAG1
	MOV		SHOW_DISP0, MIN_UN
	MOV		SHOW_DISP1, MIN_DEC
	MOV		SHOW_DISP2, HORA_UN
	MOV		SHOW_DISP3, HORA_DEC
	RJMP	TIME_UPDATED1


CHECK_FLAG1:
	CPI		FLAG, 1 
	BRNE	SKIP_TIME
	RJMP	TIME_UPDATED1

; -----------------------------------------------------------------------------
; ------------------------- CARGAR PATRONES ----------------------------
; -------------------------------------------------------------------------

TIME_UPDATED1:

    ; --- Unidades de minuto ---
    LDI     ZH, 0x01
    LDI     ZL, 0x00			; Z -> 0x0100
    ADD     ZL, SHOW_DISP0      ; Z = 0x0100 + MIN_UN
    LD      R16, Z        ; Cargar el patrón de 7-seg desde la tabla en SRAM
    STS     DIGITO_0, R16 ; Almacenar el patrón en la variable DIGITO_0

    ; --- Decenas de minuto ---
    LDI     ZH, 0x01
    LDI     ZL, 0x00
    ADD     ZL, SHOW_DISP1
    LD      R16, Z        ; Cargar el patrón de 7-seg desde la tabla en SRAM
    STS     DIGITO_1, R16 ; Almacenar el patrón en la variable DIGITO_0
    ; --- Unidades de hora ---
    LDI     ZH, 0x01
    LDI     ZL, 0x00
    ADD     ZL, SHOW_DISP2
    LD      R16, Z        ; Cargar el patrón de 7-seg desde la tabla en SRAM
    STS     DIGITO_2, R16 ; Almacenar el patrón en la variable DIGITO_0
    ; --- Decenas de hora ---
    LDI     ZH, 0x01
    LDI     ZL, 0x00
    ADD     ZL, SHOW_DISP3
    LD      R16, Z        ; Cargar el patrón de 7-seg desde la tabla en SRAM
    STS     DIGITO_3, R16 ; Almacenar el patrón en la variable DIGITO_0



SKIP_TIME:

; -----------------------------------------------------------------------------
; ------------------------- TOGGLE DE DISPLAY  ----------------------------
; -------------------------------------------------------------------------
    CPI     FLAG, 0
    BRNE    NO_LED_TOGGLE

    ; --- 3a) Toggle LED PD7 cada 500ms ---
    INC     LED_CNT
    CPI     LED_CNT, 100         ; 100 * 5ms = 500ms
    BRNE    NO_LED_TOGGLE
    CLR     LED_CNT
	SBI		PIND, 7


; -----------------------------------------------------------------------------
; ------------------------- INICIA RUTINA DE MULTIPLEXADO ----------------------------
; -------------------------------------------------------------------------

NO_LED_TOGGLE:

    ; --- 3b) Multiplexar displays ---
    ; Apagar todos los displays (PC2..PC5)
    CBI     PORTC, 5
    CBI     PORTC, 4
    CBI     PORTC, 3
    CBI     PORTC, 2

    ; Seleccionar display según DISP_CNT
    CPI     DISP_CNT, 0
    BREQ    SHOW0
    CPI     DISP_CNT, 1
    BREQ    SHOW1
    CPI     DISP_CNT, 2
    BREQ    SHOW2
    CPI     DISP_CNT, 3
    BREQ    SHOW3

SHOW0:
    SBI     PORTC, 5        ; Enciende display en PC5
    RJMP    LOAD_DISP0

SHOW1:
    SBI     PORTC, 4
    RJMP    LOAD_DISP1

SHOW2:
    SBI     PORTC, 3
    RJMP    LOAD_DISP2

SHOW3:
    SBI     PORTC, 2
    RJMP    LOAD_DISP3

LOAD_DISP0:
    LDS     R16, DIGITO_0
    RJMP    WRITE_DISPLAY

LOAD_DISP1:
    LDS     R16, DIGITO_1
    RJMP    WRITE_DISPLAY

LOAD_DISP2:
    LDS     R16, DIGITO_2
    RJMP    WRITE_DISPLAY

LOAD_DISP3:
    LDS     R16, DIGITO_3
    RJMP    WRITE_DISPLAY

WRITE_DISPLAY:
    ; Conservar PD7 (LED) y actualizar PD0..PD6
    IN      R24, PORTD
    ANDI    R24, 0x80      ; aislar bit 7
    ANDI    R16, 0x7F      ; aislar bits 0..6
    OR      R24, R16
    OUT     PORTD, R24

    INC     DISP_CNT
	CPI		DISP_CNT, 4
	BRNE	SKIP_LED_DISPLAY
	CLR		DISP_CNT

SKIP_LED_DISPLAY:

    ; --- Restaurar registros y salir de ISR ---
    POP     R16
    OUT     SREG, R16
    POP     R24
    POP     R16
    RETI

; =============================================================================
; ========================== INICIALIZAR TIMER0 ===========================
; =============================================================================

INIT_TMR0:
    LDI     R16, (1<<CS01) | (1<<CS00)  ; prescaler=64
    OUT     TCCR0B, R16
    LDI     R16, VALOR_TMR0
    OUT     TCNT0, R16
    RET
