`default_nettype none
// Two UARTs, synchronized detect, digital CARD reset/boot, host v2 proof bridge.
// The bridge owns its digest through child completion/abort and rejects busy
// replacements. SHARE_DIGEST=0 retains the captured-child regression fallback.
// This is transport, not USB or signature verification.
module firm_reader_host_uart #(
 parameter integer CLKS_PER_BIT=347,RESET_CYCLES=32,BOOT_CYCLES=4096,
 parameter integer BYTE_TIMEOUT=800000,FRAME_TIMEOUT=4000000,
 parameter integer CHILD_TIMEOUT=48000000,OP_TIMEOUT=50000000,TX_TIMEOUT=8000000,SHARE_DIGEST=1
)(
 input wire clk,reset_n,card_detect,host_rx,card_rx,
 output wire host_tx,card_tx,card_reset_n,card_present,card_operational,
 output wire busy,frame_fault,overrun,power_fault
);
`ifndef FIRM_CVC_NO_ASYNC_ATTR
 (* ASYNC_REG="TRUE" *)
`endif
 reg detect_meta,detect_sync;
 always @(posedge clk or negedge reset_n) begin
  if(!reset_n) begin detect_meta<=0;detect_sync<=0;end
  else begin detect_meta<=card_detect;detect_sync<=detect_meta;end
 end
 assign card_present=detect_sync;
 wire clear_link;
 firm_reader_card_power #(.RESET_CYCLES(RESET_CYCLES),.BOOT_CYCLES(BOOT_CYCLES)) power(
  .clk(clk),.reset_n(reset_n && !clear_link),.card_present(card_present),
  .card_reset_n(card_reset_n),.operational(card_operational),.power_fault(power_fault));
 wire request_valid,request_identity,request_ready,proof_valid,proof_ready,child_done,child_ok,cancel;
 wire [255:0] digest;
 wire [7:0] proof_data,child_error,child_status,child_remote_error;
 wire [6:0] proof_count;
 firm_reader_proof_uart #(.CLKS_PER_BIT(CLKS_PER_BIT),.TRANSACTION_CYCLES(CHILD_TIMEOUT),.ENABLE_IDENTITY(1),.CAPTURE_DIGEST(!SHARE_DIGEST)) child(
  .clk(clk),.reset_n(reset_n),.card_present(card_present),.card_ready(card_operational),.cancel(cancel),
  .request_valid(request_valid),.request_identity(request_identity),.request_digest(digest),.request_ready(request_ready),
  .busy(),.clear_link(clear_link),.card_rx(card_rx),.card_tx(card_tx),
  .proof_valid(proof_valid),.proof_data(proof_data),.proof_ready(proof_ready),
  .done(child_done),.transport_ok(child_ok),.error_code(child_error),
  .remote_status(child_status),.remote_error(child_remote_error),.proof_count(proof_count));
 wire host_rx_valid,host_tx_valid,host_tx_ready,host_tx_busy,abort_host_tx;
 wire [7:0] host_rx_data,host_tx_data;
 reg tx_start;reg [7:0] tx_latch;
 wire tx_reset_n=reset_n && !abort_host_tx;
 assign host_tx_ready=tx_reset_n && !host_tx_busy && !tx_start;
 always @(posedge clk or negedge tx_reset_n) begin
  if(!tx_reset_n) begin tx_start<=0;tx_latch<=0;end
  else begin
   tx_start<=host_tx_valid && host_tx_ready;
   if(host_tx_valid && host_tx_ready) tx_latch<=host_tx_data;
  end
 end
 uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) rx(.clk(clk),.reset_n(reset_n),.rx(host_rx),.data_out(host_rx_data),.valid(host_rx_valid));
 uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) tx(.clk(clk),.reset_n(tx_reset_n),.start(tx_start),.data_in(tx_latch),.tx(host_tx),.busy(host_tx_busy));
 firm_host_proof_bridge #(.BYTE_TIMEOUT(BYTE_TIMEOUT),.FRAME_TIMEOUT(FRAME_TIMEOUT),
  .OP_TIMEOUT(OP_TIMEOUT),.TX_TIMEOUT(TX_TIMEOUT)) bridge(
  .clk(clk),.reset_n(reset_n),.card_present(card_present),
  .host_rx_valid(host_rx_valid),.host_rx_error(1'b0),.host_rx_data(host_rx_data),
  .host_tx_valid(host_tx_valid),.host_tx_data(host_tx_data),.host_tx_ready(host_tx_ready),
  .busy(busy),.frame_fault(frame_fault),.overrun(overrun),.cancel(cancel),
  .request_valid(request_valid),.request_identity(request_identity),.request_digest(digest),.request_ready(request_ready),
  .proof_valid(proof_valid),.proof_data(proof_data),.proof_ready(proof_ready),
  .child_done(child_done),.child_ok(child_ok),.child_error(child_error),
  .child_status(child_status),.child_remote_error(child_remote_error),.abort_host_tx(abort_host_tx));
 wire unused=&{1'b0,proof_count};
endmodule
`default_nettype wire
