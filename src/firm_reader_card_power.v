`default_nettype none
// Digital insertion/reset/boot sequencing only, not power rail qualification.
module firm_reader_card_power #(
    parameter integer RESET_CYCLES=32,
    parameter integer BOOT_CYCLES=128
)(
    input wire clk, reset_n, card_present,
    output wire card_reset_n, operational,
    output reg power_fault
);
    localparam [1:0] HOLD_RESET=0,BOOT=1,READY=2;
    function integer width_for;
        input integer value;
        begin width_for=1;while((value>>width_for)>0) width_for=width_for+1;end
    endfunction
    localparam COUNT_WIDTH=width_for((RESET_CYCLES>BOOT_CYCLES?RESET_CYCLES:BOOT_CYCLES)-1);
    reg [COUNT_WIDTH-1:0] count;
    reg [1:0] state;
    reg reset_enable;
    wire invalid_context=state>READY ||
        (state==HOLD_RESET && count>=RESET_CYCLES) ||
        (state==BOOT && count>=BOOT_CYCLES) || (state==READY && count!=0);
    assign card_reset_n=card_present && reset_enable && !power_fault && !invalid_context;
    assign operational=card_reset_n && state==READY;
    always @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin state<=HOLD_RESET;count<=0;reset_enable<=0;power_fault<=0;end
        else if(!card_present) begin state<=HOLD_RESET;count<=0;reset_enable<=0;power_fault<=0;end
        else if(power_fault || invalid_context) begin
            state<=HOLD_RESET;count<=0;reset_enable<=0;power_fault<=1;
        end else case(state)
            HOLD_RESET: if(count==RESET_CYCLES-1) begin
                reset_enable<=1;count<=0;state<=BOOT;
            end else count<=count+1'b1;
            BOOT: if(count==BOOT_CYCLES-1) begin
                count<=0;state<=READY;
            end else count<=count+1'b1;
            READY: begin end
        endcase
    end
endmodule
`default_nettype wire
