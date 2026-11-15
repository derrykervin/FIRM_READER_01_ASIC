// Local queue refinement: classification only publishes metadata; unrelated
// accepted frames may populate an empty slot but can never alter a full slot.
// Arbitrary frame/decision/clear/data inputs cover simultaneous clear and
// publication priority. This is not whole-bridge formal equivalence.
module reject_metadata_invariant(input wire clk,reset_n,frame_valid,reject_decision,clear_slot,
 input wire [23:0] frame_metadata,output wire correct);
 reg pending;
 reg [23:0] original,speculative;
 wire reject_event=frame_valid && reject_decision;
 always @(posedge clk or negedge reset_n) begin
  if(!reset_n) begin pending<=0;original<=0;speculative<=0;end
  else begin
   if(reject_event && !pending) begin pending<=1;original<=frame_metadata;end
   if(frame_valid && !pending) speculative<=frame_metadata;
   if(clear_slot) pending<=0;
  end
 end
 assign correct=!pending || original==speculative;
endmodule
