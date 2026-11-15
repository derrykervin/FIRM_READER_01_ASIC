// Verify the added state always equals decode of the published command, even
// on reset/clear/error/incomplete frames. No payload or input constraints.
module registered_decode_invariant(
 input wire clk,reset_n,clear,byte_valid,input wire [7:0] byte_data,
 output wire correct
);
 wire [7:0] command;
 wire [4:0] command_class;
 firm_frame_rx #(.MAX_PAYLOAD(32)) parser(
  .clk(clk),.reset_n(reset_n),.clear(clear),.byte_valid(byte_valid),.byte_data(byte_data),
  .command(command),.command_class(command_class));
 assign correct=command_class=={command==8'h7f,command==8'h01,
  command==8'h20,command==8'h02,command==8'h10};
endmodule
