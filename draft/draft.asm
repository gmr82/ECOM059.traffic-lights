;
; file: draft.asm
; created: 2026-10-17
; authors: gmr82
;

.include "m328Pdef.inc"

.macro PUSH_CONTEXT
    push TL
    in TL, SREG
    push TL
    push TH
.endmacro

.macro POP_CONTEXT
    pop TH
    pop TL
    out SREG, TL
    pop TL
.endmacro

; registers definition
.def TL             = R16   ; temporário low
.def TH             = R17   ; temporário high
.def current_state  = R18   ; guarda o indice do estado atual (0, 1, 2...)
.def next_state     = R19   ; guarda qual será o proximo estado
.def ticks_left     = R20   ; contador de tempo decremental do estado
.def bcd_cmd        = R21   ; comando atual do bcd {otimizar}

; multiplexing registers
.def mux_flag       = R22   ; controla de quem e a vez (0=tens, 1=units) {otimizar}
.def bcd_data       = R23   ; guarda dígitos: [dddd,uuuu]

; .def blink_divider  = R24   ; conta até 144 para dar os 500ms (288Hz)
; .def blink_flags    = R28   ; registador unificado p/ flags de pisca

; mux pin definitions
.equ MUX_PORT       = PORTD
.equ MUX_PIN        = 0     ; pino PD0

; timer constants
.equ CPU_F          = 16000000                      ; 16 MHz
.equ PRESCALER      = 0b101                         ; cs12 e cs10 (Timer1)
.equ TOP_144HZ      = (CPU_F / (256 * 288)) - 1     ; (Timer0)
.equ TOP_1S         = (CPU_F / 1024) - 1            ; (Timer1)

;=============================================================================
; DATA SEGMENT (SRAM)
;=============================================================================
.dseg
.org SRAM_START
    tx_ptr: .byte 2     ; Reserva 2 bytes na SRAM para o ponteiro de envio da UART
;   ~
.cseg
;=============================================================================
; VECTOR TABLE
;=============================================================================
.org 0x0000
    rjmp RESET
;   ~
.org OC1Aaddr                   ; interrupcao do timer1 (states) [0x0016]
    rjmp TIMER1_COMPA_ISR
;   ~
.org OC0Aaddr                   ; interrupcao do timer0 (mux) [0x001C]
    rjmp TIMER0_COMPA_ISR
;   ~
.org UDREaddr                   ; interrupção de buffer UART vazio [0x0026]
    rjmp UART_UDRE_ISR
;   ~

;=============================================================================
; SYSTEM INITIALIZATION/RESET
;=============================================================================
RESET:
    ; stack pointer
    ldi TL, high(RAMEND)
    out SPH, TL
    ldi TL, low(RAMEND)
    out SPL, TL
    
    ; configura as portas
    ldi TL, 0b00111111    ; bits 0~5 como saida
    out DDRB, TL          ; portb (semaforos 1 e 2)
    out DDRC, TL          ; portc (semaforos 3 e 4)

    ldi TL, 0b11111101    ; bits 0, 2~7 como saida (1 livre para tx)
    out DDRD, TL          ; portd (mux, bcd e semaforo 5)

    ; ; liga o pull-up interno no pino PD1 (TX) para evitar lixo serial ao ligar/resetar
    ; sbi PORTD, 1

    ; configura o timer0 para o chaveamento dos displays (~288hz)
    clr mux_flag            
    
    ldi TL, (1 << WGM01)          ; modo CTC
    out TCCR0A, TL
    
    ldi TL, TOP_144HZ
    out OCR0A, TL                 ; carrega o limite da contagem (216)
    
    lds TL, TIMSK0
    sbr TL, (1 << OCIE0A)         ; habilita a interrupcao Compare Match A
    sts TIMSK0, TL

    ; configura o timer1 para a maquina de estados (1s)
    ldi TL, high(TOP_1S)
    sts OCR1AH, TL
    ldi TL, low(TOP_1S)
    sts OCR1AL, TL
    
    lds TL, TIMSK1
    sbr TL, (1 << OCIE1A) 
    sts TIMSK1, TL

    ; configura UART (9600 bps @ 16 MHz)
    clr TL
    sts UBRR0H, TL
    ldi TL, 103                   ; 16.000.000 / (16 * 9600) - 1
    sts UBRR0L, TL

    ldi TL, (1 << TXEN0)          ; habilita apenas TX (interrupção desligada)
    sts UCSR0B, TL

    ldi TL, (1 << UCSZ01) | (1 << UCSZ00)   ; frame 8 bits, 1 stop bit
    sts UCSR0C, TL

    ; banner com mensagem de reset
    ; ldi ZH, high(STR_BOOT << 1)
    ; ldi ZL, low(STR_BOOT << 1)

    ; MSG_PRINT:
    ;     lpm TL, Z+        ; lê o caractere da memória
    ;     tst TL            ; verifica se é o nulo (0x00)
    ;     breq MSG_DONE       ; se for nulo, a mensagem de reset acabou

    ; WAIT_BUFFER:
    ;     lds TH, UCSR0A               
    ;     sbrs TH, UDRE0               ; espera até o buffer da porta serial estar vazio
    ;     rjmp WAIT_BUFFER                

    ;     sts UDR0, TL                  ; dispara a letra para o terminal
    ;     rjmp MSG_PRINT                  ; repete para a próxima letra
    ; MSG_DONE:
    ;     ; mensagem de reset enviada

    ; inicia o motor de estados
    clr current_state       
    rcall LOAD_STATE

    ; liga a interrupção UDRE0 para disparar a mensagem do Estado 0
    lds TL, UCSR0B
    ori TL, (1 << UDRIE0)         
    sts UCSR0B, TL 

    ; liga os relógios (Timers 0 e 1) e as interrupções globais
    ldi TL, (1 << CS02)               ; dispara Timer0 (prescaler 256)
    out TCCR0B, TL

    ldi TL, (1 << WGM12) | PRESCALER  ; dispara Timer1 (CTC, prescaler 1024)
    sts TCCR1B, TL

    sei
;   ~
;=============================================================================
; ROUTINE: MAIN LOOP
;=============================================================================
MAIN_LOOP:
    ; nop
    rjmp MAIN_LOOP
;   ~

;=============================================================================
; SUBROUTINE: LOAD STATE
;=============================================================================
LOAD_STATE:
    ldi ZH, high(STATE_TABLE << 1)
    ldi ZL, low(STATE_TABLE << 1)

    ; calcula o offset = current_state * 8
    mov TL, current_state
    lsl TL          ; x2
    lsl TL          ; x4
    lsl TL          ; x8
    
    add ZL, TL
    clr TL
    adc ZH, TL

    ; lê e aplica PORTB
    lpm TL, Z+
    out PORTB, TL
    
    ; andi blink_flags, 0b00000000

    ; sbrc TL, 6            ; bit 6 do byte baixo = Pisca Veículos (V)
    ; sbr blink_flags, 0b00000001
    
    ; sbrc TL, 7            ; bit 7 do byte baixo = Pisca Pedestres (P)
    ; sbr blink_flags, 0b00000010

    lpm TL, Z+
    out PORTC, TL

    ; lê e aplica PORTD preservando BCD e TX      
    in TH, PORTD   
    andi TH, 0b00111111
    andi TL, 0b11000000
    or TH, TL
    out PORTD, TH 

    ; lê o endereço da string (2 bytes) diretamente para o ponteiro nativo X
    lpm TL, Z+
    sts tx_ptr, TL
    lpm TL, Z+
    sts tx_ptr+1, TL

    ; lê as variáveis de controle
    lpm next_state, Z+
    lpm ticks_left, Z+
    lpm bcd_cmd, Z+         ; '+' p/ avançar para o ponteiro
    
    rcall UPDATE_BCD
    ret
;   ~

;=============================================================================
; SUBROUTINE: EXTRACT DIGITS (DECIMAL TO BCD)
;=============================================================================
EXTRACT_DIGITS:
    ; calcula a dezena: (ticks_left * 205) / 2048
    mov TL, ticks_left
    ldi TH, 205
    mul TL, TH          ; R0:R1 = ticks_left * 205

    ; o byte mais significativo (R1) já tem o resultado de (ticks_left * 205) / 256
    mov bcd_data, R1

    ; últimos 3 bits de shift para completar a divisão por 2048 (256 * 8)
    lsr bcd_data        ; divide por 2
    lsr bcd_data        ; divide por 4
    lsr bcd_data        ; divide por 8 (dezena final pronta)

    ; calcula a unidade: ticks_left - (dezena * 10)
    ldi TH, 10
    mul bcd_data, TH    ; R0:R1 = dezena * 10 (cabe em R0, pois max é 9*10=90)
    
    sub TL, R0          ; TL = ticks_left original - (dezena * 10)
    
    swap bcd_data       ; passa a dezena pros 4 bits alto (0x43 -> 0x34)
    or bcd_data, TL     ; joga a unidade nos 4 bits baixos

    clr R1
    ret
;   ~

;=============================================================================
; SUB-ROTINA: UPDATE BCD
;=============================================================================
UPDATE_BCD:
    cpi bcd_cmd, 0
    breq BCD_ZERO

    cpi bcd_cmd, 2          ; comando 2 = desligar (apagar) o display
    breq BCD_OFF

    ; se não for para desligar, faz a matemática normal do tempo
    rcall EXTRACT_DIGITS    

    ;cpi bcd_cmd, 1          
    ;breq BCD_COUNTDOWN
    ret                     
;   ~
BCD_OFF:
    ldi TL, 0xFF            ; O valor 15 (0b1111) força o BCD a desligar os LEDs
    mov bcd_data, TL
    ldi TL, 15
    rjmp BCD_APPLY          ; aplica imediatamente
;   ~
BCD_ZERO:
    clr bcd_data               
    clr TL
;   ~
BCD_APPLY:
    ; move o valor numerico para os bits 2~5
    lsl TL                
    lsl TL                
    andi TL, 0b00111100   
    
    ; injeta no portd preservando bits 0~1 e 6~7
    in TH, PORTD         
    andi TH, 0b11000011  
    or TH, TL          
    out PORTD, TH        
    ret
;   ~

;=============================================================================
; ISR: TIMER 0 COMPARE MATCH A (MUX ~144Hz por display)
;=============================================================================
TIMER0_COMPA_ISR:
    PUSH_CONTEXT

    ; ; --- ANTI-GHOSTING (BLANKING) ---
    ; ; Força '1111' nos bits 2 a 5 do PORTD para apagar o decodificador BCD
    ; in TH, PORTD
    ; ori TH, 0b00111100   ; O 'ori' (OR) coloca 1 nos bits do BCD sem afetar os outros
    ; out PORTD, TH
    ; ; --------------------------------

    sbrc mux_flag, 0        
    rjmp MUX_UNITS
;   ~
MUX_TENS:
    ; troca o transístor (enquanto o BCD está apagado)
    sbi MUX_PORT, MUX_PIN   
    
    ; envia o número da dezena
    mov TL, bcd_data
    swap TL                 ; move a dezena do nible alto p/ o baixo
    andi TL, 0x0F           ; máscara: zera o nible alto
    rcall BCD_APPLY
    rjmp TIMER0_TOGGLE
;   ~
MUX_UNITS:
    ; troca o transístor (enquanto o BCD está apagado)
    cbi MUX_PORT, MUX_PIN   

    ; envia o número da unidade
    mov TL, bcd_data
    andi TL, 0x0F           ; máscara: pega a unidade
    rcall BCD_APPLY
;   ~
TIMER0_TOGGLE:
    ; alterna o estado da flag (0 para 1, 1 para 0) de forma nativa com XOR
    ldi TL, 1
    eor mux_flag, TL
;   ~
TIMER0_EXIT:
    POP_CONTEXT
    
    reti
;   ~

;=============================================================================
; ISR: TIMER 1 COMPARE MATCH A (1Hz)
;=============================================================================
TIMER1_COMPA_ISR:
    PUSH_CONTEXT


    push ZL
    push ZH
    push XL
    push XH
    
    cpi ticks_left, 1
    breq TIME_IS_UP

    dec ticks_left
    rcall UPDATE_BCD
    rjmp TIMER1_EXIT
;   ~ 
TIME_IS_UP: 
    mov current_state, next_state
    
    rcall LOAD_STATE  ; carrega todo o contexto do novo estado (incluindo o ponteiro X da nova string)

    ; liga a interrupção UDRE0 para iniciar a cascata de envios
    lds TL, UCSR0B
    ori TL, (1 << UDRIE0)         
    sts UCSR0B, TL
;   ~
TIMER1_EXIT:
    pop XH
    pop XL
    pop ZH
    pop ZL
    
    POP_CONTEXT
    reti
;   ~

;=============================================================================
; ISR: USART DATA REGISTER EMPTY
;=============================================================================
UART_UDRE_ISR:
    PUSH_CONTEXT
    
    push ZL
    push ZH
    
    ; carrega o ponteiro da string armazenado na SRAM para o registrador Z
    lds ZL, tx_ptr
    lds ZH, tx_ptr+1
    
    ; lê o próximo caractere da Flash e avança Z
    lpm TL, Z+

    ; salva o ponteiro Z atualizado de volta na SRAM
    sts tx_ptr, ZL
    sts tx_ptr+1, ZH
    
    ; verifica se é o final da string (0x00)
    tst TL
    breq TX_FINISHED
    
    ; se não for nulo, envia o caractere e sai
    sts UDR0, TL
    rjmp TX_EXIT
;   ~
TX_FINISHED:
    ; se chegou ao fim da string, desliga a própria interrupção UDRE0
    lds TL, UCSR0B
    andi TL, 0b11011111           ; limpa o bit 5 (UDRIE0)
    sts UCSR0B, TL
;   ~
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
; byte 0-1: [BL[V,P]; S1[G,Y,R]; S2[G,Y,R]; [S3[G,Y,R]; S4[G,Y,R]; S5[G,R]] (word)
; byte 2-3: [pointer to string message] (word)
; byte 4: [next_state]
; byte 5: [time in seconds] ¿ {1bits + 7bits} -> 1b:? + 7b:seconds ?
; byte 6: [bcd_command]
; byte 7: [alignment padding]
;=============================================================================
STATE_TABLE:    ; (CW TL4 TL3 BS TL2 TL1)
    ; STATE 0: manutention/reset (* = blink)
    .dw (0b0101001011010010)
    .dw (STR_ST_0 << 1)         ; pointer to string message
    .db 1, 5                    ; next_state, ticks_left (s)
    .db 1, 0                    ; bcd_command, alignment padding

    ; STATE 1: initial state (ALL: R)
    .dw (0b0100100111001001)
    .dw (STR_ST_1 << 1)
    .db 2, 1
    .db 2, 0

    ; STATE 2: crosswalks (just CW: G)
    .dw (0b1000100111001001)
    .dw (STR_ST_2 << 1)
    .db 3, 12
    .db 1, 0

    ; STATE 3: pedestrian crossing alert (CW: alert*)
    .dw (0b0100100111001001)
    .dw (STR_ST_3 << 1)
    .db 4, 4
    .db 1, 0

    ; STATE 4: security delay 1 (?)
    .dw (0b0100100111001001)
    .dw (STR_ST_4 << 1)
    .db 5, 2
    .db 2, 0

    ; STATE 5: southbound lanes reopened (TL1, TL2: G)
    .dw (0b0100100111100100)
    .dw (STR_ST_5 << 1)
    .db 6, 22
    .db 1, 0

    ; STATE 6: alert for the westbound (TL2: Y)
    .dw (0b0100100111010100)
    .dw (STR_ST_6 << 1)
    .db 7, 4
    .db 1, 0

    ; STATE 7: security delay 2 (ALL: R)
    .dw (0b0100100111001100)
    .dw (STR_ST_7 << 1)
    .db 8, 1
    .db 2, 0

    ; STATE 8: StoN ^ NtoWaS (TL1 e TL4: G)
    .dw (0b0110000111001100)
    .dw (STR_ST_8 << 1)
    .db 9, 60
    .db 1, 0

    ; STATE 9: main alert (TL1 e TL4: Y)
    .db 0b11001010, 0b01010001  ; .dw (0b0101000111001010)
    .dw (STR_ST_9 << 1)
    .db 10, 4
    .db 1, 0

    ; STATE 10: security delay 3 (ALL: R)
    .dw (0b0100100111001001)
    .dw (STR_ST_10 << 1)
    .db 11, 1
    .db 2, 0

    ; STATE 11: WtoSaN (TL3: G)
    .dw (0b0100110011001001)
    .dw (STR_ST_11 << 1)
    .db 12, 25
    .db 1, 0

    ; STATE 12: west to all alert (TL3: Y)
    .dw (0b0100101011001001)
    .dw (STR_ST_12 << 1)
    .db 1, 4
    .db 1, 0
;   ~
;=============================================================================
; STRINGS DE ESTADO (Terminadas em NULL com quebra de linha CR+LF)
;=============================================================================
STR_ST_0:  .db "S00: _MGMT", 13, 10, "CW: R | TL4: Y | TL3: Y | TL2: Y | TL1: Y", 13, 10, 0x00
STR_ST_1:  .db "S01: DELAY", 13, 10, "CW: R | TL4: R | TL3: R | TL2: R | TL1: R", 13, 10, 0x00
STR_ST_2:  .db "S02: CW///", 13, 10, "CW: G | TL4: R | TL3: R | TL2: R | TL1: R", 13, 10, 0x00
STR_ST_3:  .db "S03: CW***", 13, 10, "CW: R | TL4: R | TL3: R | TL2: R | TL1: R", 13, 10, 0x00
STR_ST_4:  .db "S04: DELAY", 13, 10, "CW: R | TL4: R | TL3: R | TL2: R | TL1: R", 13, 10, 0x00
STR_ST_5:  .db "S05: ?????", 13, 10, "CW: R | TL4: R | TL3: R | TL2: G | TL1: G", 13, 10, 0x00
STR_ST_6:  .db "S06: ?????", 13, 10, "CW: R | TL4: R | TL3: R | TL2: Y | TL1: G", 13, 10, 0x00
STR_ST_7:  .db "S07: DELAY", 13, 10, "CW: R | TL4: R | TL3: R | TL2: R | TL1: G", 13, 10, 0x00
STR_ST_8:  .db "S08: ?????", 13, 10, "CW: R | TL4: G | TL3: R | TL2: R | TL1: G", 13, 10, 0x00
STR_ST_9:  .db "S09: ALERT", 13, 10, "CW: R | TL4: Y | TL3: R | TL2: R | TL1: Y", 13, 10, 0x00
STR_ST_10: .db "S10: DELAY", 13, 10, "CW: R | TL4: R | TL3: R | TL2: R | TL1: R", 13, 10, 0x00
STR_ST_11: .db "S11: ?????", 13, 10, "CW: R | TL4: R | TL3: G | TL2: R | TL1: R", 13, 10, 0x00
STR_ST_12: .db "S12: ?????", 13, 10, "CW: R | TL4: R | TL3: Y | TL2: R | TL1: R", 13, 10, 0x00
;   ~
STR_BOOT:  .db "[RESET]", 0x0D, 0x0A, 0x00
;   ~