;
; semaforoforo.asm
;
; Created: 07/10/2026 11:25:39
; Authors :


; Determina um segmento de código para a FLASH
.cseg

; ==============================================
; Registradores
; ==============================================
.def state_count = r16 ; Contagem dos estados
.def serial_high = r17 ; Armazena a parte alta do endereço da mensagem do estado
.def serial_low = r18 ; Armazena a parte baixa do endereço da mensagem do estado
.def temp = r19 ; Registrador que auxilia durante o programa
.def temp2 = r20 ; Registrador que auxilia durante o programa
.def count_aux = r21 ; Conta quantas interrupções foram feitas pelo timer 1
.def dezena = r22 ; Armazena a dezena do display
.def unidade = r23 ; Armazena a unidade do display
.def display_select = r24 ; Alterna o display, entre dezena e unidade
.def s1count = r25 ; Conta 2 interrupções de 0.5s
; ==============================================


; ==============================================
; Constantes
; ==============================================
.set state_limit = 12 ; Limite de estados
.set s1_limit = 2 ; Limite de interrupções para 1s

.set d46 = 4 ; Dezena do primeiro ciclo
.set u46 = 6 ; Unidade do primeiro ciclo
.set d64 = 6 ; Dezena do estado de "aberto"
.set u64 = 4 ; Unidade do estado de "aberto"
.set d75 = 7 ; Dezena do estado de fechado
.set u75 = 5 ; Unidade do estado de fechado

#define CLOCK 16.0e6 ; Define o clock como 16MHz

; #==== Timer 0 ====#
; Será usado para o display
; Este timer só conta até 256 (tem 1 byte só)
.equ delay0 = 2 ; Define um delay de 5ms
.equ prescale0 = 0b101 ; Fixa o prescale do timer 2 em 1024
.equ prescale_div0 = 1024 ; Valor do prescale fixado
.equ TOP0 = int(((CLOCK * delay0)/(prescale_div0 * 1000)) - 1) ; Expressão que calcula o TOP0
.equ WGM0 = 0b10 ; Para configurar o timer 0 no modo ctc
; #===================

; #==== Timer 1 ====#
; Será usado para interrupção do estado
.equ delay = 500 ; Define um delay de 500ms
.equ prescale = 0b0100 ; Fixa o prescale do timer 1 em 256
.equ prescale_div = 256 ; Valor do prescale fixado
.equ TOP = int(((CLOCK * delay)/(prescale_div * 1000)) - 1) ; Expressão que calcula o TOP
.equ WGM = 0b0100 ; Pra configurar o timer 1 no modo ctc
; #===================
 
 ; #==== USART ====#
.equ baundrate = 9600 ; Define o baundrate em 9600 ideal para uma comunicação moderada
.equ UBRRvalue = int((CLOCK/(16 * baundrate)) - 1) ; Valor do UBRR
; #===================
; ==============================================



; ==============================================
; Inicia o tudo
; ==============================================
.org 0 ; Manda PC para o endereço 0
jmp reset ; Pula para o inicializador do maldito programa
; ==============================================



; ==============================================
; Tratamento da interrupção do timer 1
; ==============================================
.org OC1Aaddr ; Move o PC para o endereço da interrupção do timer 1
rjmp OCI1A_Interrupt ; Desvia para a subrotina de tratamento do timer 1
; ==============================================


; ==============================================
; Tratamento da interrupção do timer 1
; ==============================================
.org OC0Aaddr ; Move o PC para o endereço da interrupção do timer 0
rjmp TIMER0_Interrupt ; Desvia para a subrotina de tratamento do timer 0
; ==============================================



; ==============================================
; Tratamento da interrupção do serial
; ==============================================
.org UDREaddr ; Move o PC para o endereço da interrupção de envio
rjmp USART_UDRE_Interrupt ; Desvia para a subrotina de tratamento de envio da serial
; ==============================================



; ============================================================
; Reset
; ============================================================
reset:
	; ---- Inicia a pilha para podermos utilizar subrotinas ----
	ldi temp, high(RAMEND)
	out SPH, temp
	ldi temp, low(RAMEND)
	out SPL, temp
	; ----------------------------------------------------------

	
	clr state_count ; Zera o contador de estados
	clr display_select ; Zera o seletor do display
	clr s1count ; Zera o contador de interrupções para contar 1s

	rcall init_uart ; Inicializa a transmissão
	rcall init_ports ; Inicializa as portas dos leds


	rcall charge_leds ; Carrega o estado inicial dos leds
	rcall charge_serial ; Carrega a mensagem inicial
	rcall charge_runtimes ; Carrega a quantidade de vezes que o estado inicial vai rodar

	ldi dezena, d46 ; Carrega 7 do display no registrador da dezena
	ldi unidade, u46 ; Carrega 6 do display no registrador da unidade

	rcall init_timer ; Inicia o timer 1
	rcall init_timer0 ; Inicia o timer 0

	sei ; Habilita as interrupções globais
; ============================================================
	


; ============================================================
; Looping principal
; ============================================================
loop:
	jmp loop

; ============================================================



; ============================================================
; Iniciando os periféricos
; ============================================================
; #==== Inicializa as portas de saída ====#
init_ports:
	; Configura como saída de 0 - 5 para a porta B
	ldi temp, $3F
	out DDRB, temp

	; Configura como saída de 0 - 5 para a porta C
	ldi temp, $3F
	out DDRC, temp

	; Configura como saída os bits 0, 2, 3, 4 , 5, 6 e 7 para a porta D
	ldi temp, $FD
	out DDRD, temp
	
	ret
; #=====================================#


; #==== Inicializa o registrador do serial ====#
init_uart:
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

	ret
; #=====================================#


; #==== Inicia o timer 0 ====#
init_timer0:
	; Carrega o TOP do timer 0
	ldi temp, TOP0
	out OCR0A, temp

	; Habilita a interrpução pelo timer 0
	lds temp, TIMSK0
	ori temp, (1 << OCIE0A)
	sts TIMSK0, temp

	; Coloca o timer 0 no modo CTC
	ldi temp, (WGM0 << WGM00)
	out TCCR0A, temp

	; Inicia o timer 0 com o prescale 1024
	ldi temp, (prescale0 << CS00)
	out TCCR0B, temp

	ret
; #=====================================#

; #==== Inicia o timer 1 ====#
init_timer:
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

	ret
; #=====================================#
; ============================================================



; ============================================================
; Tratamento das interrupções
; ============================================================
; #==== Interrupção de transmissão do serial ====#
USART_UDRE_Interrupt:
	; Armazena inicialmente alguns registradores por precaução
	push temp
	in temp, SREG
	push temp
	push ZH
	push ZL


	; Carrega o endereço, no registrador Z, da mensagem que será enviada
	mov ZL, serial_low
	mov ZH, serial_high


	; Carrega o caracter na posição de Z e atualiza para o próximo endereço
	; Estamos enviando caracter por caracter
	lpm temp, Z+


	; Guarda o endereço atualizado para continuar o envio da mensagem
	mov serial_low, ZL
	mov serial_high, ZH


	; tst verifica se o valor de temp é 0, se for ele levanta a flag de zero no SREG
	tst temp
	; Desvia, caso tenha recebido 0, para encerrar o envio da mensagem
	breq fim_serial

	; Manda o caracter pra o UDR enviando ele pro serial
	sts UDR0, temp

	; Desvia para a saída da função
	rjmp saida_serial

	; Encerra o envio desligando a interrupção
	fim_serial:
		lds temp, UCSR0B
		andi temp, ~(1 << UDRIE0)
		sts UCSR0B, temp

	; Sai da interrupção
	saida_serial:
		pop ZL
		pop ZH
		pop temp
		out SREG, temp
		pop temp

		reti
; #=====================================#


; #==== Interrupção do timer 0 ====#
TIMER0_Interrupt:
	push temp
	in temp, SREG
	push temp
	push temp2

	; Faz um xor zerando ou setando 1 na seleção do display
	ldi temp, 1
	eor display_select, temp
	in temp, PORTD

	; Testa se vai mostrar a dezena ou a unidade
	tst display_select
	breq mostra_unidade

	mostra_dezena:
		; Joga 1 no bit de seleção da porta D
		ori temp, (1 << 0)
		mov temp2, dezena

		; Carrega no display
		rcall charge_display
		jmp saida_timer
		 
	mostra_unidade:
		; Joga 0 no bit de seleção da porta D
		andi temp, ~(1 << 0)
		mov temp2, unidade

		; Carrega no display
		rcall charge_display
		jmp saida_timer

	; Saída
	saida_timer:
		pop temp2
		pop temp
		out SREG, temp
		pop temp

		reti
; ; #=====================================#


; #==== Interrupção do timer 1 ====#
OCI1A_Interrupt:
	; Armazena inicialmente alguns registradores por precaução
	push temp
	in temp, SREG
	push temp
	push temp2
	push ZL
	push ZH

	; incrementa
	inc s1count

	; Verifica se contou 1s
	cpi s1count, s1_limit
	brne continua

	; Testa se a unidade zerou
	tst unidade
	breq decrementa_dezena

	decrementa_unidade:
		dec unidade
		clr s1count
		jmp continua

	decrementa_dezena:
		tst dezena
		breq continua
		
		dec dezena
		ldi unidade, 9
		clr s1count
		jmp continua

	continua:
		; Verifica se o contador auxiliar é 0, caso seja, pula para o próximo estado
		cpi count_aux, 0
		breq proximo_estado

		; Caso o contador não seja 0 significa que ainda não mudou de estado e decrementa ele
		dec count_aux

		; Verifica se está no estado (Fechando para pedestres), caso não esteja ele desvia pra saída
		cpi state_count, 2
		brne exit

		; Caso esteja no estado 2 faz o led vermelho piscar
		; Seta 1 no bit 7 do PIND
		; A ideia é que se escrever 1 no PIND ele inverte o valor do bit
		; Se estava 0 (LED apagado), vira 1 (LED aceso)
		; Se estava 1 (LED aceso), vira 0 (LED apagado)
		sbi PIND, 7

		rjmp exit


	; Passa para o próximo estado
	proximo_estado:
		; Incrementa para passar pro próximo estado
		inc state_count

		; Verifica se chegou ao último estado, caso não seja ele desvia para carregar o próximo estado
		cpi state_count, state_limit
		brlo estado_valido

		; Caso seja o último estado ele zera o estate_count fazendo voltar para o primeiro estado
		clr state_count

	
	; Carrega o próximo estado
	estado_valido:
		; Carrega o 64
		cpi state_count, 7
		breq carrega_64

		; Carrega o 76
		cpi state_count, 9
		breq carrega_75

		jmp continua2

		carrega_64:
			ldi dezena, d64
			ldi unidade, u64
			clr s1count
			jmp continua2

		carrega_75:
			ldi dezena, d75
			ldi unidade, u75
			clr s1count
			jmp continua2

		continua2:
			; Carrega o novo estado dos leds
			rcall charge_leds

			; Prepara para tramissão da mensagem do novo estado
			rcall charge_serial
		
			; Zera o contador do timer
			clr temp
			sts TCNT1H, temp
			sts TCNT1L, temp

			; Carrega a nova quantidade de vezes que ele vai interromper
			rcall charge_runtimes

	; Saida
	exit:
		pop ZH
		pop ZL
		pop temp2
		pop temp
		out SREG, temp
		pop temp

	reti
; #=====================================#
; ============================================================



; ============================================================
; Carregamento
; ============================================================
; #==== Carrega o estado dos leds ====#
charge_leds:
	; Configurando Z com o endereço do mapeamento dos leds
	ldi ZH, high(mapeamento << 1)
	ldi ZL, low(mapeamento << 1)

	; Multiplica o state_count por 2 para podermos fazer um incrementador dinâmico
	; Desta forma vai funcionar como um vetor em que cada estado é um índice e tem sua configuração específica
	; Isso é necessário pois no mapeamento armazenamos 2 bytes(1 palavra)
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
	; Armazena o temp para não perdermos com a próxima operação
	push temp

	; Mascara pra pegar os 6 bits
	; 3F = 00111111
	; O andi vai zerar apenas os dois últimos bits
	andi temp, $3F
	; Joga os 6 bits na porta B
	out PORTB, temp
	; Restaura temp para pegarmos os 2 bits que faltaram
	pop temp

	; Pega os dois últimos bits que não foram para PORTB
	; A ideia é fazer algo como:
	; temp = 11000000 << 1 = 10000000 e C = 1
	; temp2 = 00000000 << 1 = 00000001 e C = 0
	; temp = 10000000 << 1 = 00000000 e C = 1
	; temp2 = 00000001 << 1 = 00000011 e C = 0
	lsl temp ; Desloca todos os bits para << e joga o mais significativo no carry
	rol temp2 ; Desloca todos os bits para << e pega o bit do carry e joga no menos significativo
	lsl temp ; Desloca todos os bits para << e joga o mais significativo no carry
	rol temp2 ; Desloca todos os bits para << e pega o bit do carry e joga no menos significativo

	; Carrega mais 6 leds na porta C (De 0 - 5)
	; Copia o que está no temp2 para o temp. Isso ajuda pois depois precisaremos pegar os 2 últimos bits de temp2
	mov temp, temp2
	; Mascara pra pegar os 6 bits
	; 3F = 00111111
	andi temp, $3F
	; Joga os 6 bits na porta C
	out PORTC, temp


	; Mascara pra pegar os 2 bits
	; C0 = 110000
	; O andi vai prezervar apenas os dois primeiros bits
	andi temp2, $C0

	; Pega o que tá na porta D
	; Como a porta D também vai estar com o serial, displays e controle deles precisamos evitar sobreescrever
	in temp, PORTD

	; Zera só o que tiver nos bits que queremos
	; 3F = 00111111
	andi temp, $3F

	; Junta o que tem na porta D com o estado atual dos 2 últimos leds
	or temp, temp2
	; Joga tudo na porta D
	out PORTD, temp

	ret
; #=====================================#


; #==== Carrega a quantidade de vezes que cada interrupção vai rodar ====#
charge_runtimes:
	; Configurando Z com o endereço do mapeamento da quantidade de vezes que vai rodar em cada estado 
	ldi ZH, high(qtd_runs << 1)
	ldi ZL, low(qtd_runs << 1)

	; Soma o state_count ao endereço de Z para jogar na posição certa
	; Aqui não multiplicamos por 2 pois qtd_runs armazena de byte em byte, logo, cada indice do array tem 1 byte
	add ZL, state_count
	clr temp
	adc ZH, temp

	; Carrega o a quantidade de vezes que o estado vai rodar em count_aux
	lpm count_aux, z

	ret
; #=====================================#


; #==== Prepara para mandar a mensagem ====#
charge_serial:
	; Configurando Z com o endereço das mensagens do serial
	ldi ZH, high(serial_mensage << 1)
	ldi ZL, low(serial_mensage << 1)
	
	; Multiplica o state_count por 2 para podermos fazer um incrementador dinâmico
	; Desta forma vai funcionar como um vetor em que cada estado é um índice e tem sua configuração específica
	; Isso é necessário pois no mapeamento armazenamos 2 bytes(1 palavra)
	mov temp, state_count
	lsl temp

	; Incrementa para pegar o indice certo do mapeamento
	add ZL, temp
	clr temp
	adc ZH, temp

	; Carrega qual mensagem vamos mandar
	; Aqui ele meio que carrega como "string", ou seja, se for msg1 ele vai carregar "msg1"
	lpm serial_low, Z+ ; Pega o byte menos significativo
	lpm serial_high, Z ; Pega o byte mais significativo

	; Para transformar a mensagem em um endereço e carregar no registrador Z depois precisamos multiplicar por 2
	; É igual a essa lógica, em que i representa o estado:
	; ldi ZH, high(msgi << 1)
	; ldi ZL, low(msgi << 1)
	; após isso teremos o msg1 como um endereço pronto pra ser usado
	lsl serial_low
	rol serial_high

	; Liga a interrupção de UDR0
	; Desta forma se UDR0 estiver vazio ele vai interromper pra enviar a mensagem -_-'
	lds temp, UCSR0B
	ori temp, (1 << UDRIE0)
	sts UCSR0b, temp

	ret
; #=====================================#


; #==== Carrega o display ====#
charge_display:
	andi temp, 0b11000011

	lsl temp2
	lsl temp2

	or temp, temp2

	out PORTD, temp

	ret
; #=====================================#
; ============================================================



; ============================================================
; Dados da FLASH
; ============================================================
;#==== Mapeamento dos leds ====#
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

; Guarda o estado dos leds
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
; #=====================================#


; #==== Mapeamento da quantidade de vezes que vai acontecer as interrupções ====#
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
; #=====================================#


; #==== mensagens para mandar ====#
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
; #=====================================#


; #==== Mapeamento do serial ====#
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
; #=====================================#
; ============================================================