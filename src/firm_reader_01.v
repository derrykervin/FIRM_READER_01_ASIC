// FIRM_READER_01 v0.1: C1 binary UART host. Verilog-2001 synthesizable.
// TEST authentication only: public key and reversible rotate/XOR.
module firm_reader_01 #(
    parameter UART_CLKS_PER_BIT = 434,
    parameter RESET_CYCLES = 32,
    parameter BOOT_CYCLES = 128,
    parameter GAP_CYCLES = UART_CLKS_PER_BIT * 2,
    parameter TIMEOUT_CYCLES = UART_CLKS_PER_BIT * 400 + 4096,
    parameter [63:0] CHALLENGE = 64'h0123456789ABCDEF,
    parameter [7:0] EXPECTED_VERSION = 8'h01
)(
    input wire clk, input wire reset_n,
    input wire card_detect, // active high; external switch debounce is board-specific
    output wire card_present,
    output wire card_clk, output reg card_reset_n,
    output wire uart_tx, input wire uart_rx,
    output wire busy, output reg auth_pass, output reg auth_fail,
    output reg [7:0] card_version,
    output reg [63:0] card_id, output reg [63:0] auth_response,
    output reg [2:0] error_code,
    output wire [3:0] state_debug
);
    localparam [3:0] IDLE=0, RESET_CARD=1, BOOT=2, SEND=3, TX_ACK=4,
               TX_DONE=5, GAP=6, RECEIVE=7, CHECK=8, DONE=9, FAILED=10;
    localparam [1:0] VERSION=0, IDENTIFY=1, AUTH=2;
    reg detect_meta, detect_sync;
    reg clock_enable;
    reg [3:0] state, tx_index, rx_count;
    reg [1:0] phase;
    reg [31:0] delay_count, watchdog;
    reg tx_start;
    reg [7:0] tx_data;
    wire tx_busy, rx_valid;
    wire [7:0] rx_data;
    wire session_reset_n = reset_n & detect_sync & card_reset_n;
    wire [63:0] mixed = CHALLENGE ^ 64'hA52C91E74836BD10;
    wire [63:0] expected_response = {mixed[55:0],mixed[63:56]} ^ card_id;
    assign card_present = detect_sync;
    assign card_clk = clk & clock_enable;
    assign state_debug = state;
    assign busy = state != IDLE && state != DONE && state != FAILED;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin detect_meta<=0; detect_sync<=0; end
        else begin detect_meta<=card_detect; detect_sync<=detect_meta; end
    end
    // Enable changes on falling edges: full high pulses during insertion/removal.
    // For real FPGA clock forwarding use a board-specific clock output primitive.
    always @(negedge clk or negedge reset_n) begin
        if (!reset_n) clock_enable<=0;
        else clock_enable<=detect_sync;
    end
    uart_tx #(.CLKS_PER_BIT(UART_CLKS_PER_BIT)) u_tx(
        .clk(clk),.reset_n(session_reset_n),.start(tx_start),
        .data_in(tx_data),.tx(uart_tx),.busy(tx_busy));
    uart_rx #(.CLKS_PER_BIT(UART_CLKS_PER_BIT)) u_rx(
        .clk(clk),.reset_n(session_reset_n),.rx(uart_rx),
        .data_out(rx_data),.valid(rx_valid));
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state<=IDLE; phase<=VERSION; delay_count<=0; watchdog<=0;
            tx_index<=0; rx_count<=0; tx_start<=0; tx_data<=0;
            card_reset_n<=0; auth_pass<=0; auth_fail<=0; error_code<=0;
            card_version<=0; card_id<=0; auth_response<=0;
        end else if (!detect_sync) begin
            state<=IDLE; phase<=VERSION; delay_count<=0; watchdog<=0;
            tx_index<=0; rx_count<=0; tx_start<=0; tx_data<=0;
            card_reset_n<=0; auth_pass<=0; auth_fail<=0; error_code<=0;
            card_version<=0; card_id<=0; auth_response<=0;
        end else begin
            tx_start<=0;
            // Receive concurrently with TX completion, so an early reply is retained.
            if (state>=SEND && state<=RECEIVE) begin
                watchdog<=watchdog+1;
                if (rx_valid && rx_count < ((phase==VERSION) ? 1 : 8)) begin
                    rx_count<=rx_count+4'd1;
                    case(phase)
                        VERSION: card_version<=rx_data;
                        IDENTIFY: card_id<={card_id[55:0],rx_data};
                        AUTH: auth_response<={auth_response[55:0],rx_data};
                    endcase
                end
            end
            case(state)
                IDLE: begin state<=RESET_CARD; delay_count<=0; end
                RESET_CARD: begin
                    if(delay_count==RESET_CYCLES-1) begin
                        card_reset_n<=1; delay_count<=0; state<=BOOT;
                    end else delay_count<=delay_count+1;
                end
                BOOT: begin
                    if(delay_count==BOOT_CYCLES-1) begin
                        delay_count<=0; watchdog<=0; state<=SEND;
                    end else delay_count<=delay_count+1;
                end
                SEND: if(!tx_busy) begin
                    if(phase==VERSION) tx_data<=8'h01;
                    else if(phase==IDENTIFY) tx_data<=8'h02;
                    else if(tx_index==0) tx_data<=8'h10;
                    else tx_data<=CHALLENGE[63-(tx_index-1)*8 -: 8];
                    tx_start<=1; state<=TX_ACK;
                end
                TX_ACK: if(tx_busy) state<=TX_DONE;
                TX_DONE: if(!tx_busy) begin
                    if(phase==AUTH && tx_index<8) begin
                        tx_index<=tx_index+4'd1; delay_count<=0; state<=GAP;
                    end else state<=RECEIVE;
                end
                GAP: begin
                    if(delay_count==GAP_CYCLES-1) begin delay_count<=0; state<=SEND; end
                    else delay_count<=delay_count+1;
                end
                RECEIVE: if(rx_count==((phase==VERSION) ? 1 : 8)) begin
                    watchdog<=0; rx_count<=0; tx_index<=0;
                    if(phase==VERSION) begin
                        if(card_version!=EXPECTED_VERSION) begin
                            auth_fail<=1; error_code<=1; state<=FAILED;
                        end else begin phase<=IDENTIFY; state<=SEND; end
                    end else if(phase==IDENTIFY) begin phase<=AUTH; state<=SEND; end
                    else state<=CHECK;
                end
                CHECK: begin
                    if(auth_response==expected_response) begin auth_pass<=1; state<=DONE; end
                    else begin auth_fail<=1; error_code<=3; state<=FAILED; end
                end
                DONE: begin end // Results sticky until removal or global reset.
                FAILED: begin end
                default: begin state<=FAILED; auth_fail<=1; error_code<=4; end
            endcase
            // A whole-command deadline includes transmit, gaps, and response.
            if(state>=SEND && state<=RECEIVE && watchdog>=TIMEOUT_CYCLES-1) begin
                state<=FAILED; auth_fail<=1; auth_pass<=0; error_code<=2; tx_start<=0;
            end
        end
    end
endmodule
