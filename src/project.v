`default_nettype none
module tt_um_derrykervin_firm_reader_01 (
 input wire [7:0] ui_in, output wire [7:0] uo_out,
 input wire [7:0] uio_in, output wire [7:0] uio_out, output wire [7:0] uio_oe,
 input wire ena, input wire clk, input wire rst_n
);
 wire present, cclk, crst, tx, busy, pass, fail;
 wire [7:0] version; wire [63:0] id, response; wire [2:0] error; wire [3:0] state;
 firm_reader_01 #(.UART_CLKS_PER_BIT(347)) reader (
 .clk(clk), .reset_n(rst_n), .card_detect(ui_in[1]), .uart_rx(ui_in[0]),
 .card_present(present), .card_clk(cclk), .card_reset_n(crst), .uart_tx(tx),
 .busy(busy), .auth_pass(pass), .auth_fail(fail), .card_version(version),
 .card_id(id), .auth_response(response), .error_code(error), .state_debug(state));
 // Use a shared external oscillator for both ASICs at 40 MHz. uo[1] is a
 // reserved LOW pin: forwarding 40 MHz exceeds SKY output-pad specification.
 assign uo_out={present,fail,pass,busy,crst,1'b0,1'b0,tx};
 // Input bus ui[6:2] selects a diagnostic byte, uio is read-only output.
 assign uio_out = ui_in[6:2]==0 ? {1'b0,state,error} :
                  ui_in[6:2]==1 ? version :
                  ui_in[6:2]>=2 && ui_in[6:2]<=9 ? id[(9-ui_in[6:2])*8 +: 8] :
                  ui_in[6:2]>=10 && ui_in[6:2]<=17 ? response[(17-ui_in[6:2])*8 +: 8] : 8'h00;
 assign uio_oe=8'hff;
 wire unused=&{1'b0,ena,uio_in,ui_in[7],cclk,1'b0};
endmodule
`default_nettype wire
