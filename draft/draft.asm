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

; .def ptr_xl = r26   ; ponteiro baixo para a string
; .def ptr_xh = r27   ; ponteiro alto para a string

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

.org OC1Aaddr                   ; interrupcao do timer1 (states) [0x0016]
    rjmp TIMER1_COMPA_ISR
    
.org OC0Aaddr                   ; interrupcao do timer0 (mux) [0x001C]
    rjmp TIMER0_COMPA_ISR

.org UDREaddr                   ; interrupção de buffer UART vazio [0x0026]
    rjmp UART_UDRE_ISR
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

    ; liga o pull-up interno no pino PD1 (TX) para evitar lixo serial no arranque
    sbi PORTD, 1

    ; configura o timer0 para o chaveamento dos displays (~288hz)
    clr mux_flag            
    
    ldi temp, (1 << WGM01)          ; modo CTC
    out TCCR0A, temp
    
    ldi temp, TOP_144HZ
    out OCR0A, temp                 ; carrega o limite da contagem (216)
    
    lds temp, TIMSK0
    sbr temp, (1 << OCIE0A)         ; habilita a interrupcao Compare Match A
    sts TIMSK0, temp

    ; configura o timer1 para a maquina de estados (1s)
    ldi temp, high(TOP_1S)
    sts OCR1AH, temp
    ldi temp, low(TOP_1S)
    sts OCR1AL, temp
    
    lds temp, TIMSK1
    sbr temp, (1 << OCIE1A) 
    sts TIMSK1, temp

    ; configura UART (9600 bps @ 16 MHz)
    clr temp
    sts UBRR0H, temp
    ldi temp, 103                   ; 16.000.000 / (16 * 9600) - 1
    sts UBRR0L, temp

    ldi temp, (1 << TXEN0)          ; habilita apenas TX (interrupção desligada)
    sts UCSR0B, temp

    ldi temp, (1 << UCSZ01) | (1 << UCSZ00) ; frame 8 bits, 1 stop bit
    sts UCSR0C, temp

    ; --- INÍCIO DO AVISO DE RESET (BOOT BANNER via Polling) ---
    ldi ZH, high(STR_BOOT << 1)
    ldi ZL, low(STR_BOOT << 1)

    BOOT_PRINT:
        lpm temp, Z+        ; lê o caractere da memória
        tst temp            ; verifica se é o nulo (0x00)
        breq BOOT_DONE      ; se for nulo, a mensagem de reset acabou

    WAIT_BUFFER:
        lds temp2, UCSR0A               
        sbrs temp2, UDRE0               ; espera até o buffer da porta serial estar vazio
        rjmp WAIT_BUFFER                

        sts UDR0, temp                  ; dispara a letra para o terminal
        rjmp BOOT_PRINT                 ; repete para a próxima letra
    BOOT_DONE:
        ; --- FIM DO AVISO DE RESET ---

    ; inicia o motor de estados
    clr current_state       
    rcall LOAD_STATE

    ; liga a interrupção UDRE0 para disparar a mensagem do Estado 0
    lds temp, UCSR0B
    ori temp, (1 << UDRIE0)         
    sts UCSR0B, temp 

    ; liga os relógios (Timers 0 e 1) e as interrupções globais
    ldi temp, (1 << CS02)               ; dispara Timer0 (prescaler 256)
    out TCCR0B, temp

    ldi temp, (1 << WGM12) | PRESCALER  ; dispara Timer1 (CTC, prescaler 1024)
    sts TCCR1B, temp

    sei 
;   ~
;=============================================================================
; ROUTINE: MAIN LOOP
;=============================================================================
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

    ; calcula o offset = current_state * 8
    mov temp, current_state
    lsl temp                ; x2
    lsl temp                ; x4
    lsl temp                ; x8
    
    add ZL, temp
    clr temp
    adc ZH, temp

    ; lê e aplica PORTB
    lpm temp, Z+
    out PORTB, temp

    ; lê e aplica PORTC
    lpm temp, Z+
    out PORTC, temp

    ; lê e aplica PORTD preservando BCD e TX
    lpm temp, Z+            
    in temp2, PORTD         
    andi temp2, 0b00111111  
    andi temp,  0b11000000  
    or temp2, temp          
    out PORTD, temp2        

    ; lê as variáveis de controlo
    lpm ticks_left, Z+      
    lpm next_state, Z+      
    lpm bcd_cmd, Z+         ; '+' p/ avançar para o ponteiro
    
    ; lê o endereço da string (2 bytes) diretamente para o ponteiro nativo X
    lpm XL, Z+
    lpm XH, Z
    
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
; SUB-ROTINA: UPDATE BCD
;=============================================================================
UPDATE_BCD:
    cpi bcd_cmd, 2          ; comando 2 = desligar (Apagar) o display
    breq BCD_OFF

    ; se não for para desligar, faz a matemática normal do tempo
    rcall EXTRACT_DIGITS    

    cpi bcd_cmd, 1          
    breq BCD_COUNTDOWN
    cpi bcd_cmd, 0          
    breq BCD_ZERO
    ret                     

BCD_OFF:
    ldi temp, 15            ; O valor 15 (0b1111) força o BCD a desligar os LEDs
    mov bcd_tens, temp
    mov bcd_units, temp
    rjmp BCD_APPLY          ; aplica imediatamente

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

    ; carrega todo o contexto do novo estado (incluindo o ponteiro X da nova string)
    rcall LOAD_STATE        

    ; liga a interrupção UDRE0 para iniciar a cascata de envios
    lds temp, UCSR0B
    ori temp, (1 << UDRIE0)         
    sts UCSR0B, temp

TIMER1_EXIT:
    POP_CONTEXT
    reti
;   ~

;=============================================================================
; ISR: USART DATA REGISTER EMPTY
;=============================================================================
UART_UDRE_ISR:
    PUSH_CONTEXT
    
    ; salva o Z atual (usado pelo LOAD_STATE)
    push ZL
    push ZH
    
    ; move o ponteiro X (da string) para Z, pois o lpm exige o Z
    mov ZL, XL
    mov ZH, XH
    
    ; lê o próximo caractere e avança o ponteiro Z
    lpm temp, Z+
    
    ; atualiza o ponteiro X com a nova posição
    mov XL, ZL
    mov XH, ZH
    
    ; verifica se é o final da string (0x00)
    tst temp
    breq TX_FINISHED
    
    ; se não for nulo, envia o caractere e sai
    sts UDR0, temp
    rjmp TX_EXIT

TX_FINISHED:
    ; se chegou ao fim da string, desliga a própria interrupção UDRE0
    lds temp, UCSR0B
    andi temp, 0b11011111           ; limpa o bit 5 (UDRIE0)
    sts UCSR0B, temp

TX_EXIT:
    ; restaura o ponteiro Z e o contexto
    pop ZH
    pop ZL
    POP_CONTEXT
    reti

;   ~
;=============================================================================
; STATE MACHINE DATA (.db / .dw)
; structure (8 bytes per state):
; byte 0: [PORTB - semaforos 1 e 2]
; byte 1: [PORTC - semaforos 3 e 4]
; byte 2: [PORTD - semaforo 5 nos bits 6 e 7]
; byte 3: [time in seconds] 
; byte 4: [next_state] 
; byte 5: [bcd_command]
; byte 6-7: [pointer to string message] (word)
;=============================================================================
STATE_TABLE:
    ; ESTADO 0: Maintenance (Y intermitente / Manutenção)
    .db 0b00010010, 0b00010010  ; S1, S2, S3, S4: Y
    .db 0b10000000, 7           ; S5: R, 7s
    .db 1, 1                    ; Prox 1, BCD COUNTDOWN
    .dw (STR_ST_0 << 1)         
    
    ; ESTADO 1: Initial state (Todos Rs)
    .db 0b00100100, 0b00100100  ; S1, S2, S3, S4: R
    .db 0b10000000, 1           ; S5: R, 1s
    .db 2, 2                    ; Prox 2, BCD OFF
    .dw (STR_ST_1 << 1)         
    
    ; ESTADO 2: Crosswalks (S5: G)
    .db 0b00100100, 0b00100100  ; S1, S2, S3, S4: R
    .db 0b01000000, 12          ; S5: G, 12s
    .db 3, 1                    ; Prox 3, BCD COUNTDOWN
    .dw (STR_ST_2 << 1)         
    
    ; ESTADO 3: Pedestrian crossing alert (S5: alerta)
    .db 0b00100100, 0b00100100  ; S1, S2, S3, S4: R
    .db 0b10000000, 4           ; S5: R, 4s (No CSV: 0|1 piscar)
    .db 4, 1                    ; Prox 4, BCD COUNTDOWN
    .dw (STR_ST_3 << 1)         
    
    ; ESTADO 4: Security delay 1 (Segurança)
    .db 0b00100100, 0b00100100  ; S1, S2, S3, S4: R
    .db 0b10000000, 2           ; S5: R, 2s
    .db 5, 2                    ; Prox 5, BCD OFF
    .dw (STR_ST_4 << 1)         

    ; ESTADO 5: Southbound lanes reopened (S1 e S2: G)
    .db 0b00001001, 0b00100100  ; S1, S2: G | S3, S4: R
    .db 0b10000000, 22          ; S5: R, 22s
    .db 6, 1                    ; Prox 6, BCD COUNTDOWN
    .dw (STR_ST_5 << 1)         

    ; ESTADO 6: Alert for the westbound (S2: Y)
    .db 0b00010001, 0b00100100  ; S1: G, S2: Y | S3, S4: R
    .db 0b10000000, 4           ; S5: R, 4s
    .db 7, 1                    ; Prox 7, BCD COUNTDOWN
    .dw (STR_ST_6 << 1)         

    ; ESTADO 7: Security delay 2 (Segurança)
    .db 0b00100001, 0b00100100  ; S1: G, S2 R | S3, S4: R
    .db 0b10000000, 1           ; S5: R, 1s
    .db 8, 2                    ; Prox 8, BCD OFF
    .dw (STR_ST_7 << 1)         

    ; ESTADO 8: StoN ^ NtoWaS (S1 e S4: G)
    .db 0b00100001, 0b00001100  ; S1 R(x)->G! | S3 R, S4: G
    .db 0b10000000, 60          ; S5: R, 60s
    .db 9, 1                    ; Prox 9, BCD COUNTDOWN
    .dw (STR_ST_8 << 1)         

    ; ESTADO 9: Main alert (S1 e S4: Y)
    .db 0b00100010, 0b00010100  ; S1: Y, S2 R | S3 R, S4: Y
    .db 0b10000000, 4           ; S5: R, 4s
    .db 10, 1                   ; Prox 10, BCD COUNTDOWN
    .dw (STR_ST_9 << 1)         

    ; ESTADO 10: Security delay 3 (Segurança)
    .db 0b00100100, 0b00100100  ; S1, S2, S3, S4: R
    .db 0b10000000, 1           ; S5: R, 1s
    .db 11, 2                   ; Prox 11, BCD OFF
    .dw (STR_ST_10 << 1)        

    ; ESTADO 11: WtoSaN (S3: G)
    .db 0b00100100, 0b00100001  ; S1, S2 R | S3: G, S4 R
    .db 0b10000000, 25          ; S5: R, 25s
    .db 12, 1                   ; Prox 12, BCD COUNTDOWN
    .dw (STR_ST_11 << 1)        

    ; ESTADO 12: West to all alert (S3: Y)
    .db 0b00100100, 0b00100010  ; S1, S2 R | S3: Y, S4 R
    .db 0b10000000, 4           ; S5: R, 4s
    .db 1, 1                    ; Prox 1, BCD COUNTDOWN
    .dw (STR_ST_12 << 1)        
;   ~
;=============================================================================
; STRINGS DE ESTADO (Terminadas em NULL com quebra de linha CR+LF)
;=============================================================================
STR_ST_0:  .db "E0: Maintenance (Manutencao)", 0x0D, 0x0A, 0x00
STR_ST_1:  .db "E1: Initial state (Todos R)", 0x0D, 0x0A, 0x00
STR_ST_2:  .db "E2: Crosswalks (S5 G)", 0x0D, 0x0A, 0x00
STR_ST_3:  .db "E3: Pedestrian crossing alert", 0x0D, 0x0A, 0x00
STR_ST_4:  .db "E4: Security delay 1", 0x0D, 0x0A, 0x00
STR_ST_5:  .db "E5: Southbound lanes reopened", 0x0D, 0x0A, 0x00
STR_ST_6:  .db "E6: Alert for the westbound", 0x0D, 0x0A, 0x00
STR_ST_7:  .db "E7: Security delay 2", 0x0D, 0x0A, 0x00
STR_ST_8:  .db "E8: StoN & NtoWaS (S1, S4 G)", 0x0D, 0x0A, 0x00
STR_ST_9:  .db "E9: Main alert (S1, S4 Y)", 0x0D, 0x0A, 0x00
STR_ST_10: .db "E10: Security delay 3", 0x0D, 0x0A, 0x00
STR_ST_11: .db "E11: WtoSaN (S3 G)", 0x0D, 0x0A, 0x00
STR_ST_12: .db "E12: West to all alert (S3 Y)", 0x0D, 0x0A, 0x00
;   ~
STR_BOOT:  .db "[RESET]", 0x0D, 0x0A, 0x00
;   ~