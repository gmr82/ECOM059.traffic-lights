;
; semaforoforo.asm
;
; Created: 07/10/2026 11:25:39
; Authors :


; Determina um segmento de código para a FLASH
.cseg

; Manda PC para o endereço 0
.org 0

; Define um registrador para armazenar o contador de estados
.def state_count = r16
.def serial_high = r17
.def serial_low = r18

; Registrador auxiliar
.def temp = r19
.def temp2 = r20
.def count_aux = r21

.def dezena = r22
.def unidade = r23

; Limite de estados
.set state_limit = 12

; Pula para o inicializador do maldito programa
jmp reset

; Move o PC para o endereço da interrupção do timer
.org OC1Aaddr
; Desvia para a subrotina de tratamento do timer
rjmp OCI1A_Interrupt

; Move o PC para o endereço da interrupção de envio
.org UDREaddr
; Desvia para a subrotina de tratamento de envio da serial
rjmp USART_UDRE_Interrupt

; ============================================================
; Inicia todos os parâmetros
; ============================================================
reset:
	; ---- Inicia a pilha para podermos utilizar subrotinas ----
	ldi temp, high(RAMEND)
	out SPH, temp
	ldi temp, low(RAMEND)
	out SPL, temp
	; ----------------------------------------------------------


	; ---- Configurações iniciais ----
	; zera state_count
	clr state_count

	; Define o clock como 16MHz
	#define CLOCK 16.0e6
	; Define um delay de 500ms
	.equ delay = 500
	; Fixa o prescale em 256
	.equ prescale = 0b0100
	; Valor do prescale fixado
	.equ prescale_div = 256
	; Expressão que calcula o TOP
	.equ TOP = int(((CLOCK * delay)/(prescale_div * 1000)) - 1)

	; Define o baundrate em 9600 ideal para uma comunicação moderada
	.equ baundrate = 9600
	; Valor do UBRR
	.equ UBRRvalue = int((CLOCK/(16 * baundrate)) - 1)

	; Pra configurar o timer no modo ctc (contar tanto cansa)
	.equ WGM = 0b0100
	; ----------------------------------------------------------


	; ---- Configura o serial ----
	; configurando o Baund rate register
	ldi temp, high(UBRRvalue)
	sts UBRR0H, temp
	ldi temp, low(UBRRvalue)
	sts UBRR0L, temp

	; Configurando o USART control and status registrer C
	; UMSEL01 E UMSEL01 = 0 0 ---> Modo assincrono
	; UPM01 E UPM00 = 0 0 ----> Paridade desativada
	; USBS0 = 0 ----> 1 Bit de parada
	; UCSZ02, UCSZ01 E UCSZ00 = 0 1 1 ----> 8 bits por transimissão, ideal para transmitir caracteres
	ldi temp, (0b11 << UCSZ00)
	sts UCSR0C, temp

	; Habilidando a transmissão
	ldi temp, (1 << TXEN0)
	sts UCSR0B, temp

	rcall charge_serial
	; ----------------------------------------------------------


	; ---- Configura porta como saída ----
	; Configura como saída de 0 - 5 para a porta B
	ldi temp, $3F
	out DDRB, temp

	; Configura como saída de 0 - 5 para a porta C
	ldi temp, $3F
	out DDRC, temp

	; Configura como saída os bits 0, 2, 3, 4 , 5, 6 e 7 para a porta D
	ldi temp, $FD
	out DDRD, temp
	; ----------------------------------------------------------


	; ---- Carregamento inicial da entrada ----
	rcall charge_leds
	; ----------------------------------------------------------


	; ---- Carregamento inicial da qtd de vezes que vai rodar a miséria ----
	rcall charge_runtimes
	; ----------------------------------------------------------


	; ---- Configura inicialmente o timer ----
	
	; Carrega o valor de top no registrador OCR1A
	ldi temp, high(TOP)
	sts OCR1AH, temp
	ldi temp, low(TOP)
	sts OCR1AL, temp

	;Habilita as interrupções do timer
	;Carrega o valor do registrador de controle do timer, evita carregar bagunça no TIMSK1
	lds temp, TIMSK1
	;Seta OCIE1A para 1, habilitando as interrupções via timer
	sbr temp, 1 << OCIE1A
	;Carrega para o registrador de controle do timer
	sts TIMSK1, temp

	; Configurar o timer bolado pra contar (maldito só sabe contar até 0.5s	)
	; WGM&0b11 = 0b0100 & 0b0011 = 0b0000 
	ldi temp, ((WGM&0b11) << WGM10)
	sts TCCR1A, temp

	;2 bits mais significativos de WGM e seleção de clock
	; WGM >> 2 = 0b0100 >> 2 = 0b0001
	; (WGM >> 2) << WGM12 = (0b0001 << 3) = 0b0001000
	; (PRESCALE << CS10) = 0b101 << 0 = 0b101
	; 0b0001000 | 0b101 = 0b0001101
	ldi temp, ((WGM>>2)<<WGM12)|(prescale << CS10)
	sts TCCR1B, temp
	; ----------------------------------------------------------


	; ---- Habilita globalmente as interrupções ----
	sei
	; ----------------------------------------------------------
; ============================================================
	

; ============================================================
; Looping principal
; ============================================================
loop:
	jmp loop

; ============================================================


; ============================================================
; Tratamento da interrupção de mensagem
; ============================================================
USART_UDRE_Interrupt:
	push temp
	in temp, SREG
	push temp

	push ZH
	push ZL

	; Carrega o endereço da mensagem no registrador Z
	mov ZL, serial_low
	mov ZH, serial_high

	; Carrega o byte que tá em Z e incrementa
	lpm temp, Z+

	; Guarda o endereço do Z
	mov serial_low, ZL
	mov serial_high, ZH

	; tst verifica se o valor de temp é 0, se for ele levanta a flag de zero no SREG
	tst temp
	; Desvia para desligar a baixaria
	breq fim_serial

	; Manda o caracter pra o UDR
	sts UDR0, temp

	; Desvia para a saída da função
	rjmp saida_serial

	; Desliga a interrupção da serial
	fim_serial:
		lds temp, UCSR0B
		andi temp, ~(1 << UDRIE0)
		sts UCSR0B, temp

	; Saida
	saida_serial:
		pop ZL
		pop ZH
		pop temp
		out SREG, temp
		pop temp

		reti
; ============================================================


; ============================================================
; Tratamendo da interrupção de timer
; ============================================================
OCI1A_Interrupt:
	; conceitualmente salvando o sreg ('_')
	push temp
	in temp, SREG
	push temp

	push temp2
	push ZL
	push ZH

	; Verifica o contador para passar para o próximo estado
	cpi count_aux, 0
	breq proximo_estado

	; Caso o contador não seja 0 decrementa ele
	dec count_aux

	; Verifica se está no estado (Fechando para pedestres), assim faz o pisca pisca pro led
	cpi state_count, 2
	brne exit

	; Seta 1 no bit 7 do PIND
	; A ideia é que se escrever 1 no PIND ele inverte o valor do bit
	; Se estava 0 (LED apagado), vira 1 (LED aceso)
	; Se estava 1 (LED aceso), vira 0 (LED apagado)
	sbi PIND, 7

	rjmp exit


	proximo_estado:
		; Passa pro próximo estado
		inc state_count

		; Verifica se chegou ao último estado
		cpi state_count, state_limit
		; Caso não pula pra carregar o próximo estado
		brlo estado_valido

		; Volta pro estado inicial
		clr state_count

	
	; Carrega o próximo estado
	estado_valido:
		; Carrega os leds
		rcall charge_leds

		; Prepara a ablação do caba
		rcall charge_serial
		
		; Zera o contador do timer
		clr temp
		sts TCNT1H, temp
		sts TCNT1L, temp

		; Carregamento inicial da qtd de vezes que vai rodar a miséria
		rcall charge_runtimes

	; Saida
	; Despusha o SREG
	exit:
		pop ZH
		pop ZL
		pop temp2
		pop temp
		out SREG, temp
		pop temp

	reti
; ============================================================


; ============================================================
; Carrega o mapeamento dos leds
; ============================================================
charge_leds:
	; Configurando z com o mapeamento inicial
	ldi ZH, high(mapeamento << 1)
	ldi ZL, low(mapeamento << 1)

	; Multiplica o state_count por 2
	mov temp, state_count
	lsl temp

	; Incrementa para pegar o indice certo do mapeamento
	add ZL, temp
	clr temp
	adc ZH, temp

	; Carrega os leds do estado
	lpm temp, Z+ ; Lê o menos significativo
	lpm temp2, Z ; Lê o mais significativo

	; Carrega 6 leds na porta B (De 0 - 5)
	push temp
	; Mascara pra pegar os 6 bits
	andi temp, $3F
	out PORTB, temp
	pop temp

	; Gambiarra pra pegar os dois últimos bits que não foram para PORTB
	; O lsl desloca os bits para << e joga o bit 7 no carry
	; O rol desloca os bits de temp2 para << e joga o carry no bit 0
	lsl temp
	rol temp2
	lsl temp
	rol temp2

	; Carrega mais 6 leds na porta C (De 0 - 5)
	mov temp, temp2
	; Mascara pra pegar os 6 bits
	andi temp, $3F
	out PORTC, temp

	; Troca os 4 primeiros bits com os últimos 4 bits
	; Mascara pra pegar os 2 bits
	andi temp2, $C0
	; Pega o que tá na porta D
	in temp, PORTD
	; Zera só o que tiver nos bits que queremos
	andi temp, $3F
	; Junta com o que tem no temp 2
	or temp, temp2
	; Escreve na porta D
	out PORTD, temp
	; ----------------------------------------------------------

	ret
; ============================================================


; ============================================================
; Carrega a quantidade de vezes que cada interrupção vai rodar
; ============================================================
charge_runtimes:
	; Carregando o top inicial em Z
	ldi ZH, high(qtd_runs << 1)
	ldi ZL, low(qtd_runs << 1)

	; Funciona igual ao carregamento do próximo estado
	add ZL, state_count
	clr temp
	adc ZH, temp

	; Carrega o byte menos significativo do top
	lpm count_aux, z

	ret
; ============================================================


; ============================================================
; Prepara para mandar a mensagem
; ============================================================
charge_serial:
	ldi ZH, high(serial_mensage << 1)
	ldi ZL, low(serial_mensage << 1)
	
	; Multiplica por 2
	mov temp, state_count
	lsl temp

	; Incrementa certo
	add ZL, temp
	clr temp
	adc ZH, temp

	; Carrega da memoria
	lpm serial_low, Z+
	lpm serial_high, Z

	; Multiplica por 2, isso será usado como endereço para a mensagem enviada
	lsl serial_low
	rol serial_high

	; Liga a interrupção de UDR0
	; Desta forma se UDR0 estiver vazio ele vai interromper pra enviar a mensagem -_-'
	lds temp, UCSR0B
	ori temp, (1 << UDRIE0)
	sts UCSR0b, temp

	ret
; ============================================================


; ============================================================
; Mapeamento dos leds marotos

; StoN
; Semaforo 1: verde (bit 0), amarelo (bit 1), vermelho (bit 2)
; StoW
; Semaforo 2: verde (bit 3), amarelo (bit 4), vermelho (bit 5)
; WtoSaN
; Semaforo 3: verde (bit 6), amarelo (bit 7), vermelho (bit 8)
; NtoWaS
; Semaforo 4: verde (bit 9), amarelo (bit 10), vermelho (bit 11)
; Nc+Sc
; Semaforo 5: verde (bit 12), vermelho(bit 13)
; ============================================================
; Semaforo 1
.equ S1_G = (1 << 0)
.equ S1_Y = (1 << 1)
.equ S1_R = (1 << 2)

; Semaforo 2
.equ S2_G = (1 << 3)
.equ S2_Y = (1 << 4)
.equ S2_R = (1 << 5)

; Semaforo 3
.equ S3_G = (1 << 6)
.equ S3_Y = (1 << 7)
.equ S3_R = (1 << 8)


; Semaforo 4
.equ S4_G = (1 << 9)
.equ S4_Y = (1 << 10)
.equ S4_R = (1 << 11)

; Semaforo 5
.equ S5_G = (1 << 12)
.equ S5_R = (1 << 13)


mapeamento:
	; Estado 1
	.dw S1_R|S2_R|S3_R|S4_R|S5_R
	; Estado 2
	.dw S1_R|S2_R|S3_R|S4_R|S5_G 
	; Estado 3
	; O de pedestre pisca
	.dw S1_R|S2_R|S3_R|S4_R|S5_R
	; Estado 4
	.dw S1_R|S2_R|S3_R|S4_R|S5_R
	; Estado 5
	.dw S1_G|S2_G|S3_R|S4_R|S5_R
	; Estado 6
	.dw S1_G|S2_Y|S3_R|S4_R|S5_R
	; Estado 7
	.dw S1_G|S2_R|S3_R|S4_R|S5_R
	; Estado 8
	.dw S1_G|S2_R|S3_R|S4_G|S5_R
	; Estado 9
	.dw S1_Y|S2_R|S3_R|S4_Y|S5_R
	; Estado 10
	.dw S1_R|S2_R|S3_R|S4_R|S5_R
	; Estado 11
	.dw S1_R|S2_R|S3_G|S4_R|S5_R
	; Estado 12
	.dw S1_R|S2_R|S3_Y|S4_R|S5_R
; ============================================================


; ============================================================
; Mapeamento da quantidade de vezes que vai acontecer as interrupções
; ============================================================
qtd_runs:
; Definindo os limites de execuções, algumas interrupções terão que rodar mais vezes
; É o caso do estado 2 em que o timer precisa bater 12s mas o maldito timer só sabe contar até 4.2
; Tive que botar pra repetir no 3 só pra ele ficar piscando D:
; 1s -> vai rodar 2 vezes de 0.5s
; 12s -> vai rodar 24 vezes de 0.5s
; 4s -> vai rodar 8 vezes de 0.5s
; 2s -> vai rodar 4 vezes de 0.5s
; 22s -> vai rodar 44 vezes de 0.5s
; 4s -> vai rodar 8 vezes de 0.5s
; 1s -> vai rodar 2 vezes de 0.5s
; 60s -> vai rodar 120 vezes de 0.5s
; 4s -> vai rodar 8 vezes de 0.5s
; 25s -> vai rodar 60 vezes de 0.5s
; 4s -> vai rodar 8 vezes de 0.5s
.db 1, 23, 7, 3, 43, 7, 1, 119, 7, 1, 49, 7
; ============================================================


; ============================================================
; mensagens para mandar
; ============================================================
; Estado 1
msg1:
    .db "S1: Vermelho", 13, 10, "S2: Vermelho", 13, 10, "S3: Vermelho", 13, 10, "S4: Vermelho", 13, 10, "S5: Vermelho", 13, 10, 13, 10, 0, 0

; Estado 2
msg2:
    .db "S1: Vermelho", 13, 10, "S2: Vermelho", 13, 10, "S3: Vermelho", 13, 10, "S4: Vermelho", 13, 10, "S5: Verde", 13, 10, 13, 10, 0

; Estado 3
msg3:
    .db "S1: Vermelho", 13, 10, "S2: Vermelho", 13, 10, "S3: Vermelho", 13, 10, "S4: Vermelho", 13, 10, "S5: Vermelho piscando", 13, 10, 13, 10, 0

; Estado 4
msg4:
	.db "S1: Vermelho", 13, 10, "S2: Vermelho", 13, 10, "S3: Vermelho", 13, 10, "S4: Vermelho", 13, 10, "S5: Vermelho", 13, 10, 13, 10, 0, 0

; Estado 5
msg5:
	.db "S1: Verde", 13, 10, "S2: Verde", 13, 10, "S3: Vermelho", 13, 10, "S4: Vermelho", 13, 10,"S5: Vermelho", 13, 10, 13, 10, 0, 0

; Estado 6
msg6:
	.db "S1: Verde", 13, 10, "S2: Amarelo", 13, 10, "S3: Vermelho", 13, 10, "S4: Vermelho", 13, 10, "S5: Vermelho", 13, 10, 13, 10, 0, 0

; Estado 7
msg7:
	.db "S1: Verde", 13, 10, "S2: Vermelho", 13, 10, "S3: Vermelho", 13, 10, "S4: Vermelho", 13, 10, "S5: Vermelho", 13, 10, 13, 10, 0

; Estado 8
msg8:
	.db "S1: Verde", 13, 10, "S2: Vermelho", 13, 10, "S3: Vermelho", 13, 10, "S4: Verde", 13, 10, "S5: Vermelho", 13, 10, 13, 10, 0, 0

; Estado 9
msg9:
	.db "S1: Amarelo", 13, 10, "S2: Vermelho", 13, 10, "S3: Vermelho", 13, 10, "S4: Amarelo", 13, 10, "S5: Vermelho", 13, 10, 13, 10, 0, 0

; Estado 10
msg10:
	.db "S1: Vermelho", 13, 10, "S2: Vermelho", 13, 10, "S3: Vermelho", 13, 10, "S4: Vermelho", 13, 10, "S5: Vermelho", 13, 10, 13, 10, 0, 0

; Estado 11
msg11:
	.db "S1: Vermelho", 13, 10, "S2: Vermelho", 13, 10, "S3: Verde", 13, 10, "S4: Vermelho", 13, 10, "S5: Vermelho", 13, 10, 13, 10, 0

; Estado 12
msg12:
	.db "S1: Vermelho", 13, 10, "S2: Vermelho", 13, 10, "S3: Amarelo", 13, 10, "S4: Vermelho", 13, 10, "S5: Vermelho", 13, 10, 13, 10, 0
; ============================================================


; ============================================================
; Mapeamento do serial
; ============================================================
serial_mensage:
	.dw msg1
	.dw msg2
	.dw msg3
	.dw msg4
	.dw msg5
	.dw msg6
	.dw msg7
	.dw msg8
	.dw msg9
	.dw msg10
	.dw msg11
	.dw msg12
; ============================================================


; ============================================================
; Mapeamento do BCD
; ============================================================
; 1s -> 0 - Dezena, 1 - Unidade
; 12s -> 1 - Dezena, 2 - Unidade
; 4s -> 0 - Dezena, 4 - Unidade
; 2s -> 0 - Dezena, 2 - Unidade
; 22s -> 2 - Dezena, 2 - Unidade
; 4s -> 0 - Dezena, 4 - Unidadde
; 1s -> 0 - Dezena, 1 - Unidade
; 60s -> 6 - Dezena, 0 - Unidade
; 4s -> 0 - Dezena, 4 - Unidadde
; 25s -> 2 - Dezena, 5 - Unidade
; 4s -> 0 - Dezena, 4 - Unidadde
bcd_maping:
	.db 0, 1
	.db 1, 2
	.db 0, 4
	.db 0, 2
	.db 2, 2
	.db 
; ============================================================