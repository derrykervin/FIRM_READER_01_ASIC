`default_nettype none
module tt_um_derrykervin_firm_reader_01(
 input wire [7:0] ui_in,output wire [7:0] uo_out,
 input wire [7:0] uio_in,output wire [7:0] uio_out,output wire [7:0] uio_oe,
 input wire ena,clk,rst_n
);
 wire enabled=ena && rst_n;
 wire host_tx,card_tx,card_reset_n,card_present,card_operational;
 wire busy,frame_fault,overrun,power_fault;
 firm_reader_host_uart #(.CLKS_PER_BIT(347)) core(
  .clk(clk),.reset_n(enabled),.card_detect(ui_in[1]),.host_rx(ui_in[2]),.card_rx(ui_in[0]),
  .host_tx(host_tx),.card_tx(card_tx),.card_reset_n(card_reset_n),.card_present(card_present),
  .card_operational(card_operational),.busy(busy),.frame_fault(frame_fault),.overrun(overrun),.power_fault(power_fault));
 // Shared external40MHz oscillator; no output pin forwards the clock.
 // No pin is AUTH_PASS: the host must verify the actual signature.
 assign uo_out=enabled?{card_present,overrun|power_fault,frame_fault,busy,card_reset_n,1'b0,host_tx,card_tx}:8'h03;
 assign uio_out=enabled?{4'd0,power_fault,overrun,frame_fault,card_operational}:8'h00;
 assign uio_oe=enabled?8'hff:8'h00;
 wire unused=&{1'b0,ui_in[7:3],uio_in};
endmodule
`default_nettype wire
