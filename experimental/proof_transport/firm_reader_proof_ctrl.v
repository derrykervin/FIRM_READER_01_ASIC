`default_nettype none
// One outstanding A1 digest / D0 tentative proof / F0 terminal transaction.
// This controller qualifies transport only. No cryptographic verification.
// The adapter MUST reset CARD and flush both UART directions while clear_link
// is high, deassert card_ready during reset, and assert it only after boot.
module firm_reader_proof_ctrl #(
    parameter integer TRANSACTION_CYCLES=48000000,ENABLE_IDENTITY=0,CAPTURE_DIGEST=1
)(
    input wire clk, reset_n, card_present, card_ready, cancel,
    input wire request_valid,request_identity,
    input wire [255:0] request_digest,
    output wire request_ready, busy, clear_link,
    output wire tx_valid,
    output wire [7:0] tx_data,
    input wire tx_ready,
    input wire rx_valid, rx_error,
    input wire [7:0] rx_data,
    output wire proof_valid,
    output wire [7:0] proof_data,
    input wire proof_ready,
    output reg done, transport_ok,
    output reg [7:0] error_code, remote_status, remote_error,
    output reg [6:0] proof_count
);
    localparam [3:0] IDLE=0, RESET_CARD=1, BOOT=2, SEND=3,
        TAG=4, DATA=5, STATUS=6, ERROR=7, COUNT=8, OUTPUT=9, FLUSH=10;
    localparam [7:0] E_TIMEOUT=1,E_REMOVED=2,E_CANCEL=3,E_FRAME=4,
        E_REMOTE=5,E_CONTEXT=6;
    function integer cw;
        input integer n;integer v;
        begin cw=1;v=n-1;while(v>1) begin cw=cw+1;v=v>>1;end end
    endfunction
    reg [3:0] state;
    reg [cw(TRANSACTION_CYCLES)-1:0] age;
    reg [255:0] digest;
    reg [7:0] proof[0:83];
    reg identity_mode;
    wire [6:0] expected_count=identity_mode?7'd84:7'd64;
    reg [5:0] send_index;reg [6:0] output_index;
    wire invalid_parameter=TRANSACTION_CYCLES<1;
    wire invalid_context=state>FLUSH || proof_count>expected_count ||
        (state==SEND && send_index>32);
    wire live=reset_n && card_present && !cancel && !invalid_parameter && !invalid_context;
    wire expired=age>=TRANSACTION_CYCLES-1;
    assign busy=state!=IDLE;
    assign request_ready=live && card_ready && state==IDLE;
    assign clear_link=reset_n && (state==RESET_CARD || state==FLUSH || invalid_parameter);
    assign tx_valid=live && card_ready && state==SEND && !expired;
    // CAPTURE_DIGEST=0 is private to the host bridge integration: that owner
    // holds request_digest immutable until this controller completes or aborts.
    // Standalone/default mode retains capture and destructive shift semantics.
    // For accepted byte indices 1..32, -index modulo32 selects bytes31..0.
    wire [4:0] borrowed_byte_index=5'd0-send_index[4:0];
    wire [7:0] digest_byte=CAPTURE_DIGEST ? digest[255:248] :
        request_digest[{borrowed_byte_index,3'b000}+:8];
    assign tx_data=send_index==0 ? (identity_mode?8'ha0:8'ha1) : digest_byte;
    assign proof_valid=live && card_ready && state==OUTPUT && !expired;
    assign proof_data=proof_valid ? proof[output_index] : 8'h00;
    // Stored proof is public and is logically invalidated, not physically erased.
    task fail;
        input [7:0] code;
        begin
            state<=FLUSH;done<=1;transport_ok<=0;error_code<=code;
            proof_count<=0;output_index<=0;send_index<=0;digest<=0;
        end
    endtask
    always @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin
            state<=IDLE;identity_mode<=0;age<=0;digest<=0;send_index<=0;output_index<=0;
            done<=0;transport_ok<=0;error_code<=0;remote_status<=0;
            remote_error<=0;proof_count<=0;
        end else begin
            done<=0;
            if(state==FLUSH) begin
                // Do not rearm on the same ready epoch that failed.
                if(!card_ready) state<=IDLE;
            end else if(state!=IDLE) begin
                age<=age+1'b1;
                if(invalid_parameter || invalid_context) fail(E_CONTEXT);
                else if(!card_present) fail(E_REMOVED);
                else if(cancel) fail(E_CANCEL);
                else if(expired) fail(E_TIMEOUT);
                else if(rx_error && state!=RESET_CARD && state!=BOOT) fail(E_FRAME);
                else if(!card_ready && state!=RESET_CARD && state!=BOOT) fail(E_CONTEXT);
                else case(state)
                    RESET_CARD: if(!card_ready) state<=BOOT;
                    BOOT: if(card_ready) state<=SEND;
                    SEND: begin
                        if(rx_valid) fail(E_FRAME);
                        else if(tx_valid && tx_ready) begin
                            if(send_index!=0) digest<={digest[247:0],8'h00};
                            if(identity_mode || send_index==32) state<=TAG;
                            else send_index<=send_index+1'b1;
                        end
                    end
                    TAG: if(rx_valid) begin
                        if(rx_data==8'hd0 && proof_count<expected_count) state<=DATA;
                        else if(rx_data==8'hf0) state<=STATUS;
                        else fail(E_FRAME);
                    end
                    DATA: if(rx_valid) begin
                        proof[proof_count]<=rx_data;
                        proof_count<=proof_count+1'b1;state<=TAG;
                    end
                    STATUS: if(rx_valid) begin remote_status<=rx_data;state<=ERROR;end
                    ERROR: if(rx_valid) begin remote_error<=rx_data;state<=COUNT;end
                    COUNT: if(rx_valid) begin
                        // Status low nibble: active=0, finished=1, committed=1,
                        // error=0; bit4 cannot advertise a remaining byte.
                        // Bits5/6 are live diagnostics, not terminal qualification.
                        // CARD clears digest ownership when the session starts.
                        if(proof_count!=expected_count || rx_data!=expected_count || remote_error!=0 ||
                           (remote_status & 8'h9f)!=8'h06) fail(E_REMOTE);
                        else begin state<=OUTPUT;output_index<=0;transport_ok<=1;end
                    end
                    OUTPUT: begin
                        if(rx_valid) fail(E_FRAME);
                        else if(proof_valid && proof_ready) begin
                            if(output_index==expected_count-1) begin state<=IDLE;done<=1;end
                            else output_index<=output_index+1'b1;
                        end
                    end
                    default: fail(E_CONTEXT);
                endcase
            end else begin
                age<=0;
                if(!card_present || cancel) begin transport_ok<=0;proof_count<=0;end
                if(request_valid && request_ready) begin
                    identity_mode<=ENABLE_IDENTITY ? request_identity : 1'b0;
                    digest<=request_digest;send_index<=0;output_index<=0;
                    proof_count<=0;remote_status<=0;remote_error<=0;
                    error_code<=0;transport_ok<=0;state<=RESET_CARD;
                end
            end
        end
    end
endmodule
`default_nettype wire
