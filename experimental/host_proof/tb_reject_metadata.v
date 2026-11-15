`timescale 1ns/1ps
module tb_reject_metadata;
 reg clk=0;always #5 clk=~clk;
 reg reset_n=0,tx_ready=0,frame=0;
 reg [15:0] seq=0;reg [7:0] cmd=0;
 wire overrun;integer n;
 firm_host_proof_bridge #(.TX_TIMEOUT(1000)) dut(
  .clk(clk),.reset_n(reset_n),.card_present(1'b1),
  .host_rx_valid(1'b0),.host_rx_error(1'b0),.host_rx_data(8'd0),
  .host_tx_valid(),.host_tx_data(),.host_tx_ready(tx_ready),
  .busy(),.frame_fault(),.overrun(overrun),.cancel(),.request_valid(),
  .request_identity(),.request_digest(),.request_ready(1'b0),
  .proof_valid(1'b0),.proof_data(8'd0),.proof_ready(),
  .child_done(1'b0),.child_ok(1'b0),.child_error(8'd0),
  .child_status(8'd0),.child_remote_error(8'd0),.abort_host_tx());
 task publish;input [15:0] s;input [7:0] c;
  begin @(negedge clk);seq=s;cmd=c;frame=1;
   @(negedge clk);frame=0;end
 endtask
 initial begin
  // Direct parser publication injection isolates queue ownership from CRC
  // parsing, which remains covered by the complete host regression.
  force dut.frame_valid=frame;force dut.sequence_id=seq;
  force dut.command=cmd;force dut.command_class=5'd0;
  force dut.response_flag=1'b0;force dut.payload_length=8'd0;
  repeat(2) @(negedge clk);reset_n=1;
  publish(16'h1234,8'h71);@(negedge clk);
  if(!dut.tx_active || dut.tx_sequence!==16'h1234 || dut.tx_command!==8'h71)
   $fatal(1,"first rejection metadata mismatch");
  publish(16'h5678,8'h72);
  if(!dut.reject_pending || dut.reject_sequence!==16'h5678 || dut.reject_command!==8'h72)
   $fatal(1,"queued rejection metadata mismatch");
  publish(16'h9abc,8'h73);
  if(!overrun || !dut.reject_pending || dut.reject_sequence!==16'h5678 || dut.reject_command!==8'h72)
   $fatal(1,"full rejection metadata overwritten");
  tx_ready=1;n=0;
  while(dut.tx_sequence!==16'h5678 && n<80) begin @(negedge clk);n=n+1;end
  if(n>=80 || dut.tx_command!==8'h72 || dut.reject_pending)
   $fatal(1,"queued rejection metadata not transmitted");
  reset_n=0;#1;
  if(dut.reject_pending || dut.reject_sequence!==0 || dut.reject_command!==0)
   $fatal(1,"rejection reset mismatch");
  $display("PASS rejection metadata queue hold, overrun, exact dispatch, reset");$finish;
 end
 initial begin #100000;$fatal(1,"watchdog");end
endmodule
