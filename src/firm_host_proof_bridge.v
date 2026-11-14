`default_nettype none
// Host v2 envelope / PROVE profile1. All success means transport only.
// One host request outstanding. One bounded rejection slot handles accidental
// pipelining; overrun is explicit and never overwrites the active operation.
module firm_host_proof_bridge #(
 parameter integer BYTE_TIMEOUT=800000,FRAME_TIMEOUT=4000000,
 parameter integer OP_TIMEOUT=50000000,TX_TIMEOUT=8000000
)(
 input wire clk,reset_n,card_present,
 input wire host_rx_valid,host_rx_error,input wire [7:0] host_rx_data,
 output wire host_tx_valid,output reg [7:0] host_tx_data,input wire host_tx_ready,
 output wire busy,output reg frame_fault,overrun,output wire cancel,
 output wire request_valid,request_identity,output wire [255:0] request_digest,input wire request_ready,
 input wire proof_valid,input wire [7:0] proof_data,output wire proof_ready,
 input wire child_done,child_ok,input wire [7:0] child_error,child_status,child_remote_error,
 output reg abort_host_tx
);
 localparam [1:0] IDLE=0,START=1,RUN=2;
 localparam [7:0] OK=0,E_LENGTH=2,E_BUSY=4,E_TIMEOUT=5,E_NO_CARD=6,
  E_DEVICE=8,E_UNSUPPORTED=9,E_SEQUENCE=11,E_CANCEL=12;
 reg [1:0] operation;
 reg [31:0] op_age,tx_age;
 reg [255:0] digest;
 reg [7:0] result[0:83];
 reg [7:0] work_command;
 wire [6:0] expected_count=work_command==2?7'd84:7'd64;
 wire identity_frame=command==2 && payload_length==0;
 wire [255:0] incoming_value=identity_frame?256'd0:incoming_digest;
 reg [6:0] result_count;
 reg [15:0] work_sequence,highwater;
 reg cache_valid,primary_pending;
 reg [1:0] retries;
 reg [7:0] result_status,result_remote_status,result_remote_error;
 reg reject_pending;
 reg [15:0] reject_sequence;
 reg [7:0] reject_command,reject_status,reject_detail;
 reg tx_active,tx_primary;
 reg [15:0] tx_sequence,tx_crc;
 reg [7:0] tx_command,tx_status,tx_detail,tx_error,tx_count,tx_index;
 wire frame_valid,response_flag,parse_error;
 wire [15:0] sequence_id;
 wire [7:0] command,payload_length;
 wire [255:0] payload;
 wire [2:0] parse_error_code;
 wire [255:0] incoming_digest;
 genvar b;
 generate for(b=0;b<32;b=b+1) begin: reorder
  assign incoming_digest[255-b*8-:8]=payload[b*8+:8];
 end endgenerate
 firm_frame_rx #(.MAX_PAYLOAD(32),.BYTE_TIMEOUT_CYCLES(BYTE_TIMEOUT),
  .FRAME_TIMEOUT_CYCLES(FRAME_TIMEOUT)) parser(
  .clk(clk),.reset_n(reset_n),.clear(host_rx_error),.byte_valid(host_rx_valid),.byte_data(host_rx_data),
  .frame_valid(frame_valid),.sequence_id(sequence_id),.command(command),.response_flag(response_flag),
  .payload_length(payload_length),.payload(payload),.error_valid(parse_error),.error_code(parse_error_code));
 wire op_expired=op_age>=OP_TIMEOUT-1;
 wire tx_expired=tx_age>=TX_TIMEOUT-1;
 assign request_valid=reset_n && operation==START && card_present && !op_expired;
 assign request_digest=digest;
 assign request_identity=work_command==2;
 assign proof_ready=reset_n && operation==RUN && card_present && result_count<expected_count && !op_expired;
 assign cancel=reset_n && operation!=IDLE &&
  (op_expired || !card_present || (frame_valid && !response_flag &&
    command==8'h7f && payload_length==0));
 assign busy=operation!=IDLE || primary_pending || tx_active || reject_pending;
 assign host_tx_valid=reset_n && tx_active && !tx_expired &&
  !(tx_primary && tx_status==OK && !card_present);
 wire [7:0] payload_size=tx_count+4;
 wire [7:0] crc_hi_index=payload_size+9;
 function [15:0] crc_byte;
  input [15:0] c0;input [7:0] value;integer i;reg [15:0] c;
  begin c=c0^{value,8'h00};for(i=0;i<8;i=i+1)c=c[15]?(c<<1)^16'h1021:c<<1;crc_byte=c;end
 endfunction
 always @* begin
  host_tx_data=0;
  case(tx_index)
   0:host_tx_data=8'ha5;1:host_tx_data=8'h5a;2:host_tx_data=2;3:host_tx_data=1;
   4:host_tx_data=tx_sequence[15:8];5:host_tx_data=tx_sequence[7:0];
   6:host_tx_data=tx_command;7:host_tx_data=0;8:host_tx_data=payload_size;
   9:host_tx_data=tx_status;10:host_tx_data=tx_detail;
   11:host_tx_data=tx_error;12:host_tx_data=tx_count;
   default: begin
    if(tx_index==crc_hi_index) host_tx_data=tx_crc[15:8];
    else if(tx_index==crc_hi_index+1) host_tx_data=tx_crc[7:0];
    else if(tx_index>=13 && tx_index<crc_hi_index) host_tx_data=result[tx_index-13];
   end
  endcase
 end
 task reject;
  input [7:0] status_code,detail;
  begin
   if(!reject_pending) begin
    reject_pending<=1;reject_sequence<=sequence_id;reject_command<=command;
    reject_status<=status_code;reject_detail<=detail;
   end else overrun<=1;
  end
 endtask
 task complete_failure;
  input [7:0] code;
  begin
   operation<=IDLE;result_status<=code;result_remote_status<=child_status;
   result_remote_error<=child_remote_error;result_count<=0;
   cache_valid<=card_present;primary_pending<=1;
  end
 endtask
 always @(posedge clk or negedge reset_n) begin
  if(!reset_n) begin
   operation<=IDLE;op_age<=0;tx_age<=0;digest<=0;result_count<=0;
   work_sequence<=0;work_command<=8'h10;highwater<=0;cache_valid<=0;primary_pending<=0;retries<=0;
   result_status<=0;result_remote_status<=0;result_remote_error<=0;
   reject_pending<=0;reject_sequence<=0;reject_command<=0;reject_status<=0;reject_detail<=0;
   tx_active<=0;tx_primary<=0;tx_sequence<=0;tx_crc<=16'hffff;
   tx_command<=0;tx_status<=0;tx_detail<=0;tx_error<=0;tx_count<=0;tx_index<=0;
   frame_fault<=0;overrun<=0;abort_host_tx<=0;
  end else begin
   abort_host_tx<=0;
   if(parse_error || host_rx_error) frame_fault<=1;
   if(!card_present) cache_valid<=0;
   // The primary result cannot be overwritten until its full response is owned
   // by the TX adapter. Host traffic never resets/corrupts an active digest.
   if(operation!=IDLE) begin
    op_age<=op_age+1;
    if(!card_present) begin complete_failure(E_NO_CARD);result_remote_status<=0;result_remote_error<=0;end
    else if(cancel) begin
     complete_failure(op_expired?E_TIMEOUT:E_CANCEL);result_remote_status<=0;result_remote_error<=0;
    end
    else if(op_expired) begin complete_failure(E_TIMEOUT);result_remote_status<=0;result_remote_error<=0;end
    else case(operation)
     START: if(request_valid && request_ready) operation<=RUN;
     RUN: begin
      if(proof_valid && proof_ready) begin result[result_count]<=proof_data;result_count<=result_count+1'b1;end
      if(child_done) begin
       if(child_ok && result_count==expected_count) begin
        operation<=IDLE;result_status<=OK;result_remote_status<=child_status;
        result_remote_error<=child_remote_error;cache_valid<=1;primary_pending<=1;
       end else complete_failure(child_error==1?E_TIMEOUT:child_error==2?E_NO_CARD:
        child_error==3?E_CANCEL:E_DEVICE);
      end
     end
     default:complete_failure(E_DEVICE);
    endcase
   end
   if(frame_valid) begin
    if(response_flag) reject(E_UNSUPPORTED,0);
    else if(command==8'h10 || command==8'h02) begin
     if((command==8'h10 && payload_length!=32) || (command==2 && payload_length!=0)) reject(E_LENGTH,0);
     else if(operation!=IDLE || primary_pending || tx_active || reject_pending) reject(E_BUSY,0);
     else if(!card_present) reject(E_NO_CARD,0);
     else if(cache_valid && sequence_id==work_sequence) begin
      if(command==work_command && incoming_value==digest && retries<2) begin primary_pending<=1;retries<=retries+1'b1;end
      else reject(E_SEQUENCE,0);
     end else if(sequence_id==0 || sequence_id<=highwater) reject(E_SEQUENCE,0);
     else begin
      digest<=incoming_value;work_command<=command;work_sequence<=sequence_id;highwater<=sequence_id;
      operation<=START;op_age<=0;result_count<=0;cache_valid<=0;retries<=0;
     end
    end else if(command==8'h20 && payload_length==0) reject(OK,{7'd0,busy});
    else if(command==8'h01 && payload_length==0) reject(OK,8'h22); // v2, profile1
    else if(command==8'h7f && payload_length==0) begin
     if(operation==RUN) reject(OK,0);
     else if(operation==START) begin complete_failure(E_CANCEL);result_remote_status<=0;result_remote_error<=0;reject(OK,0);end
     else reject(E_BUSY,0);
    end else reject(E_UNSUPPORTED,0);
   end
   if(tx_active) begin
    tx_age<=tx_age+1;
    if(tx_expired || (tx_primary && tx_status==OK && !card_present)) begin
     tx_active<=0;abort_host_tx<=1;frame_fault<=1;
    end else if(host_tx_valid && host_tx_ready) begin
     if(tx_index>=2 && tx_index<crc_hi_index) tx_crc<=crc_byte(tx_crc,host_tx_data);
     if(tx_index==crc_hi_index+1) tx_active<=0;
     else tx_index<=tx_index+1'b1;
    end
   end else begin
    tx_age<=0;tx_index<=0;tx_crc<=16'hffff;
    if(primary_pending) begin
     primary_pending<=0;tx_active<=1;tx_primary<=1;tx_sequence<=work_sequence;tx_command<=work_command;
     tx_status<=card_present?result_status:E_NO_CARD;
     tx_detail<=result_remote_status;tx_error<=result_remote_error;
     tx_count<=result_status==OK && card_present ? expected_count : 0;
    end else if(reject_pending) begin
     reject_pending<=0;tx_active<=1;tx_primary<=0;tx_sequence<=reject_sequence;tx_command<=reject_command;
     tx_status<=reject_status;tx_detail<=reject_detail;tx_error<=0;tx_count<=0;
    end
   end
  end
 end
 wire unused=&{1'b0,parse_error_code};
endmodule
`default_nettype wire
