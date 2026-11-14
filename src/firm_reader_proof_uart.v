`default_nettype none
// UART adapter for the byte controller. request_digest is already assembled by
// the owning host bridge, or captured locally in standalone/default mode.
module firm_reader_proof_uart #(
    parameter integer CLKS_PER_BIT=347, TRANSACTION_CYCLES=48000000,ENABLE_IDENTITY=0,CAPTURE_DIGEST=1
)(
    input wire clk,reset_n,card_present,card_ready,cancel,
    input wire request_valid,request_identity,input wire [255:0] request_digest,
    output wire request_ready,busy,clear_link,
    input wire card_rx,output wire card_tx,
    output wire proof_valid,output wire [7:0] proof_data,input wire proof_ready,
    output wire done,transport_ok,
    output wire [7:0] error_code,remote_status,remote_error,
    output wire [6:0] proof_count
);
    wire link_reset_n=reset_n && card_present && card_ready && !clear_link;
    wire tx_valid,tx_ready,tx_busy,rx_valid;
    wire [7:0] tx_data,rx_data;
    reg tx_start;
    reg [7:0] tx_latch;
    assign tx_ready=link_reset_n && !tx_busy && !tx_start;
    always @(posedge clk or negedge link_reset_n) begin
        if(!link_reset_n) begin tx_start<=0;tx_latch<=0;end
        else begin
            tx_start<=tx_valid && tx_ready;
            if(tx_valid && tx_ready) tx_latch<=tx_data;
        end
    end
    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) tx(.clk(clk),.reset_n(link_reset_n),
        .start(tx_start),.data_in(tx_latch),.tx(card_tx),.busy(tx_busy));
    // Existing uart_rx suppresses bad-stop bytes and waits for idle after BREAK.
    // It has no framing-error output: malformed/truncated input reaches the
    // controller's total deadline, rather than being labelled a valid frame.
    uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) rx(.clk(clk),.reset_n(link_reset_n),
        .rx(card_rx),.data_out(rx_data),.valid(rx_valid));
    firm_reader_proof_ctrl #(.TRANSACTION_CYCLES(TRANSACTION_CYCLES),.ENABLE_IDENTITY(ENABLE_IDENTITY),.CAPTURE_DIGEST(CAPTURE_DIGEST)) ctrl(
        .clk(clk),.reset_n(reset_n),.card_present(card_present),.card_ready(card_ready),
        .cancel(cancel),.request_valid(request_valid),.request_identity(request_identity),.request_digest(request_digest),
        .request_ready(request_ready),.busy(busy),.clear_link(clear_link),
        .tx_valid(tx_valid),.tx_data(tx_data),.tx_ready(tx_ready),
        .rx_valid(rx_valid),.rx_error(1'b0),.rx_data(rx_data),
        .proof_valid(proof_valid),.proof_data(proof_data),.proof_ready(proof_ready),
        .done(done),.transport_ok(transport_ok),.error_code(error_code),
        .remote_status(remote_status),.remote_error(remote_error),.proof_count(proof_count));
endmodule
`default_nettype wire
