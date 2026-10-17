;
; file: draft.asm
; created: 2026-10-17
; authors: gmr82
;

.include "m328Pdef.inc"

.macro PUSH_CONTEXT
    push temp
    in temp, SREG
    push temp
.endmacro

.macro POP_CONTEXT
    pop temp
    out SREG, temp
    pop temp
.endmacro

; registers definition
.def temp           = r16
.def temp2          = r17
.def current_state  = r18   ; guarda o indice do estado atual (0, 1, 2...)
.def ticks_left     = r19   ; contador de tempo decremental do estado
.def next_state     = r20   ; guarda qual sera o proximo estado
.def bcd_cmd        = r21   ; comando atual do bcd

; multiplexing registers
.def mux_flag       = r22   ; controla de quem e a vez (0=tens, 1=units)
.def bcd_tens       = r23   ; guarda o digito da dezena
.def bcd_units      = r24   ; guarda o digito da unidade

; mux pin definitions
.equ MUX_PORT       = PORTD
.equ MUX_DDR        = DDRD
.equ MUX_PIN        = 0     ; pino pd0

; timer constants
.equ PRESCALER      = 0b101 ; cs12 e cs10 (Timer1)
.equ TOP_1S         = 15624 ; (Timer1) (1s @ 16mhz c/ prescaler = 1024)
.equ TOP_144HZ      = 216   ; 16MHz / (256 * 288Hz) - 1 (Timer0) TOP = (16.000.000 / (256 * 288)) - 1 = 216

;=============================================================================
; VECTOR TABLE
;=============================================================================
.org 0x0000
    rjmp RESET

.org OC1Aaddr               ; interrupcao do timer1 (states) [0x0016]
    rjmp TIMER1_COMPA_ISR  
    
.org OC0Aaddr 
    rjmp TIMER0_COMPA_ISR   ; interrupcao do timer0 (mux) [0x001C]
;   ~

;=============================================================================
; SYSTEM INITIALIZATION
;=============================================================================
RESET:
    ; stack pointer
    ldi temp, high(RAMEND)
    out SPH, temp
    ldi temp, low(RAMEND)
    out SPL, temp
    
    ; configura as portas
    ldi temp, 0b00111111    ; bits 0~5 como saida
    out DDRB, temp          ; portb (semaforos 1 e 2)
    out DDRC, temp          ; portc (semaforos 3 e 4)

    ldi temp, 0b11111101    ; bits 0, 2~7 como saida (1 livre para tx)
    out DDRD, temp          ; portd (mux, bcd e semaforo 5)

    ; configura o timer0 para o chaveamento dos displays (~288hz)
    clr mux_flag            
    
    ldi temp, (1 << WGM01)          ; modo CTC
    out TCCR0A, temp
    
    ldi temp, TOP_144HZ
    out OCR0A, temp                 ; carrega o limite da contagem (216)
    
    ldi temp, (1 << CS02)           ; prescaler 256
    out TCCR0B, temp
    
    lds temp, TIMSK0
    sbr temp, (1 << OCIE0A)         ; habilita a interrupcao Compare Match A
    sts TIMSK0, temp

    ; configura o timer1 para a maquina de estados (1s)
    ldi temp, high(TOP_1S)
    sts OCR1AH, temp
    ldi temp, low(TOP_1S)
    sts OCR1AL, temp

    ldi temp, (1 << WGM12)  
    sts TCCR1B, temp
    
    lds temp, TIMSK1
    sbr temp, (1 << OCIE1A) 
    sts TIMSK1, temp

    ; inicia o motor de estados
    clr current_state       
    rcall LOAD_STATE        

    ; liga o timer1 e as interrupcoes globais
    ldi temp, (1 << WGM12) | PRESCALER
    sts TCCR1B, temp
    sei                     

MAIN_LOOP:
    nop
    rjmp MAIN_LOOP
;   ~

;=============================================================================
; SUBROUTINE: LOAD STATE
;=============================================================================
LOAD_STATE:
    ldi ZH, high(STATE_TABLE << 1)
    ldi ZL, low(STATE_TABLE << 1)

    ; calcula o offset = current_state * 6
    mov temp, current_state
    lsl temp                
    mov temp2, temp         
    lsl temp                
    add temp, temp2         
    
    add ZL, temp
    clr temp
    adc ZH, temp

    ; le e aplica portb
    lpm temp, Z+
    out PORTB, temp

    ; le e aplica portc
    lpm temp, Z+
    out PORTC, temp

    ; le e aplica portd preservando bcd e tx
    lpm temp, Z+            
    in temp2, PORTD         
    andi temp2, 0b00111111  
    andi temp,  0b11000000  
    or temp2, temp          
    out PORTD, temp2        

    ; le as variaveis de controle
    lpm ticks_left, Z+      
    lpm next_state, Z+      
    lpm bcd_cmd, Z          
    
    rcall UPDATE_BCD
    ret
;   ~

;=============================================================================
; SUBROUTINE: EXTRACT DIGITS (DECIMAL TO BCD)
;=============================================================================
EXTRACT_DIGITS:
    mov temp, ticks_left    
    clr bcd_tens          

DIV_LOOP:
    cpi temp, 10            
    brlo DIV_END            
    subi temp, 10           
    inc bcd_tens          
    rjmp DIV_LOOP           

DIV_END:
    mov bcd_units, temp   
    ret
;   ~

;=============================================================================
; SUBROUTINE: UPDATE BCD
;=============================================================================
UPDATE_BCD:
    rcall EXTRACT_DIGITS    ; atualiza os valores de tens e units

    cpi bcd_cmd, 1          
    breq BCD_COUNTDOWN
    cpi bcd_cmd, 0          
    breq BCD_ZERO
    ret                     

BCD_COUNTDOWN:
    mov temp, ticks_left    
    rjmp BCD_APPLY

BCD_ZERO:
    clr temp                
    clr bcd_tens
    clr bcd_units

BCD_APPLY:
    ; move o valor numerico para os bits 2~5
    lsl temp                
    lsl temp                
    andi temp, 0b00111100   
    
    ; injeta no portd preservando bits 0~1 e 6~7
    in temp2, PORTD         
    andi temp2, 0b11000011  
    or temp2, temp          
    out PORTD, temp2        
    ret
;   ~

;=============================================================================
; ISR: TIMER 0 COMPARE MATCH A (MUX ~144Hz por display)
;=============================================================================
TIMER0_COMPA_ISR:
    PUSH_CONTEXT

    ; --- ANTI-GHOSTING (BLANKING) ---
    ; Força '1111' nos bits 2 a 5 do PORTD para apagar o decodificador BCD
    in temp2, PORTD
    ori temp2, 0b00111100   ; O 'ori' (OR) coloca 1 nos bits do BCD sem afetar os outros
    out PORTD, temp2
    ; --------------------------------

    sbrc mux_flag, 0        
    rjmp MUX_UNITS

MUX_TENS:
    ; troca o transístor PRIMEIRO (enquanto o BCD está apagado)
    sbi MUX_PORT, MUX_PIN   
    
    ; envia o número da dezena DEPOIS
    mov temp, bcd_tens
    rcall BCD_APPLY

    ; prepara para a próxima rodada
    ldi temp, 1
    mov mux_flag, temp
    rjmp TIMER0_EXIT

MUX_UNITS:
    ; troca o transístor PRIMEIRO (enquanto o BCD está apagado)
    cbi MUX_PORT, MUX_PIN   

    ; envia o número da unidade DEPOIS
    mov temp, bcd_units
    rcall BCD_APPLY

    ; prepara para a próxima rodada
    clr mux_flag
    
TIMER0_EXIT:
    POP_CONTEXT
    reti
;   ~

;=============================================================================
; ISR: TIMER 1 COMPARE MATCH A (1Hz)
;=============================================================================
TIMER1_COMPA_ISR:
    PUSH_CONTEXT

    cpi ticks_left, 0
    breq TIME_IS_UP

    dec ticks_left
    rcall UPDATE_BCD
    rjmp TIMER1_EXIT

TIME_IS_UP: 
    mov current_state, next_state
    rcall LOAD_STATE        

TIMER1_EXIT:
    POP_CONTEXT
    reti
;   ~

;=============================================================================
; STATE MACHINE DATA (.db)
; structure (6 bytes per state):
; byte 0: [PORTB - semaforos 1 e 2]
; byte 1: [PORTC - semaforos 3 e 4]
; byte 2: [PORTD - semaforo 5 nos bits 6 e 7]
; byte 3: [time in seconds] 
; byte 4: [next_state] 
; byte 5: [bcd_command]
;=============================================================================
STATE_TABLE:
    ; ESTADO 0: Maintenance (Amarelo intermitente / Manutenção)
    .db 0b00010010, 0b00010010  ; S1,S2,S3,S4 em Amarelo
    .db 0b10000000, 7          ; S5 Vermelho, 11s
    .db 1, 1                    ; Prox 1, BCD Conta
    
    ; ESTADO 1: Initial state (Todos Vermelhos)
    .db 0b00100100, 0b00100100  ; S1,S2,S3,S4 em Vermelho
    .db 0b10000000, 1           ; S5 Vermelho, 1s
    .db 2, 0                    ; Prox 2, BCD Zera/Pausa
    
    ; ESTADO 2: Crosswalks (S5 Verde)
    .db 0b00100100, 0b00100100  ; S1,S2,S3,S4 em Vermelho
    .db 0b01000000, 12          ; S5 Verde, 12s
    .db 3, 1                    ; Prox 3, BCD Conta
    
    ; ESTADO 3: Pedestrian crossing alert (S5 alerta)
    .db 0b00100100, 0b00100100  ; S1,S2,S3,S4 em Vermelho
    .db 0b10000000, 4           ; S5 Vermelho, 4s (No CSV: 0|1 piscar)
    .db 4, 1                    ; Prox 4, BCD Conta
    
    ; ESTADO 4: Security delay 1 (Segurança)
    .db 0b00100100, 0b00100100  ; S1,S2,S3,S4 em Vermelho
    .db 0b10000000, 2           ; S5 Vermelho, 2s
    .db 5, 0                    ; Prox 5, BCD Zera/Pausa

    ; ESTADO 5: Southbound lanes reopened (S1 e S2 Verde)
    .db 0b00001001, 0b00100100  ; S1,S2 em Verde | S3,S4 em Vermelho
    .db 0b10000000, 22          ; S5 Vermelho, 22s
    .db 6, 1                    ; Prox 6, BCD Conta

    ; ESTADO 6: Alert for the westbound (S2 Amarelo)
    .db 0b00010001, 0b00100100  ; S1 Verde, S2 Amarelo | S3,S4 em Vermelho
    .db 0b10000000, 4           ; S5 Vermelho, 4s
    .db 7, 1                    ; Prox 7, BCD Conta

    ; ESTADO 7: Security delay 2 (Segurança)
    .db 0b00100001, 0b00100100  ; S1 Verde, S2 Vermelho | S3,S4 em Vermelho
    .db 0b10000000, 1           ; S5 Vermelho, 1s
    .db 8, 0                    ; Prox 8, BCD Zera/Pausa

    ; ESTADO 8: StoN ^ NtoWaS (S1 e S4 Verde)
    .db 0b00100001, 0b00001100  ; S1 Vermelho(x)->Verde! | S3 Vermelho, S4 Verde
    .db 0b10000000, 60          ; S5 Vermelho, 60s
    .db 9, 1                    ; Prox 9, BCD Conta

    ; ESTADO 9: Main alert (S1 e S4 Amarelo)
    .db 0b00100010, 0b00010100  ; S1 Amarelo, S2 Vermelho | S3 Vermelho, S4 Amarelo
    .db 0b10000000, 4           ; S5 Vermelho, 4s
    .db 10, 1                   ; Prox 10, BCD Conta

    ; ESTADO 10: Security delay 3 (Segurança)
    .db 0b00100100, 0b00100100  ; S1,S2,S3,S4 em Vermelho
    .db 0b10000000, 1           ; S5 Vermelho, 1s
    .db 11, 0                   ; Prox 11, BCD Zera/Pausa

    ; ESTADO 11: WtoSaN (S3 Verde)
    .db 0b00100100, 0b00100001  ; S1,S2 Vermelho | S3 Verde, S4 Vermelho
    .db 0b10000000, 25          ; S5 Vermelho, 25s
    .db 12, 1                   ; Prox 12, BCD Conta

    ; ESTADO 12: West to all alert (S3 Amarelo)
    .db 0b00100100, 0b00100010  ; S1,S2 Vermelho | S3 Amarelo, S4 Vermelho
    .db 0b10000000, 4           ; S5 Vermelho, 4s
    .db 1, 1                    ; Prox 1, BCD Conta
;   ~