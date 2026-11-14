`timescale 1ns/1ps
// Actual serial pads -> CPU firmware -> mailbox -> real I2C RTL, synthetic device bytes.
module tb_identity_system;
 parameter CPB=16,DIV=2;
 reg identity_mode=0;integer host_capture_fd;
 // 64 bytes x (tag + payload) x 10 UART bits = 1280*CPB cycles.
 // 1600*CPB + 10000 includes 25% serialization and software margin.
 localparam SERIAL_DRAIN=1600*CPB+10000;
 localparam TOTAL=3000000+30000*DIV;
 reg clk=0;always #12.5 clk=~clk;
 reg rst_n=0,ena=1,present=1,slave_scl=0,slave_sda=0;
 wire rx,card_rst_n,card_ready,reader_busy,host_tx;
 reg host_rx=1;
 wire frame_fault,overrun,power_fault,reader_present;
 integer proof_seen=0,request_number=0;
 reg [7:0] host_requests[0:1279],host_expected[0:1279],host_lengths[0:9],host_request_lengths[0:9];
 wire [7:0] reader_uo,reader_out,reader_oe;
 tt_um_derrykervin_firm_reader_01 reader(.ui_in({5'd0,host_rx,present,tx}),
  .uo_out(reader_uo),.uio_in(8'd0),.uio_out(reader_out),.uio_oe(reader_oe),.ena(ena),.clk(clk),.rst_n(rst_n));
 assign rx=reader_uo[0];assign host_tx=reader_uo[1];assign card_rst_n=reader_uo[3];
 assign reader_busy=reader_uo[4];assign frame_fault=reader_uo[5];assign reader_present=reader_uo[7];
 assign card_ready=reader_out[0];assign overrun=reader_out[2];assign power_fault=reader_out[3];
 defparam reader.core.CLKS_PER_BIT=CPB;
 defparam reader.core.RESET_CYCLES=5;
 defparam reader.core.BOOT_CYCLES=40;
 defparam reader.core.BYTE_TIMEOUT=CPB*100;
 defparam reader.core.FRAME_TIMEOUT=CPB*1000;
 defparam reader.core.CHILD_TIMEOUT=TOTAL+100000;
 defparam reader.core.OP_TIMEOUT=TOTAL+200000;
 defparam reader.core.TX_TIMEOUT=CPB*1500;
 always @(posedge clk) if(!ena &&(reader_oe!==0 || reader_uo!==8'h03))$fatal(1,"Reader TT ENA isolation");
 task send_host_byte;input [7:0] value;integer i;
  begin
   @(negedge clk);host_rx=0;repeat(CPB) @(negedge clk);
   for(i=0;i<8;i=i+1)begin host_rx=value[i];repeat(CPB)@(negedge clk);end
   host_rx=1;repeat(CPB)@(negedge clk);
  end
 endtask
 task read_host_byte;output [7:0] value;integer i;
  begin
   @(negedge host_tx);repeat(CPB/2)@(posedge clk);#1;
   if(host_tx!==0)$fatal(1,"host system UART start");
   for(i=0;i<8;i=i+1)begin repeat(CPB)@(posedge clk);#1;value[i]=host_tx;end
   repeat(CPB)@(posedge clk);#1;if(host_tx!==1)$fatal(1,"host system UART stop");
  end
 endtask
 task read_host_frame;input integer index;integer i;reg [7:0] value;
  begin
   for(i=0;i<host_lengths[index];i=i+1)begin
    read_host_byte(value);$fwrite(host_capture_fd,"%02x",value);
    if(value!==host_expected[index*128+i])$fatal(1,"host system response mismatch index=%0d byte=%0d got=%h expected=%h",index,i,value,host_expected[index*128+i]);
   end
   $fwrite(host_capture_fd,"\n");$fflush(host_capture_fd);
   proof_seen=host_expected[index*128+12];
  end
 endtask
 wire [7:0] rom_addr,pc,r0,gpio;
 reg [15:0] rom[0:255];wire [15:0] rom_data=rom[rom_addr];
 wire halted,busy,ok,sl,dl,tx,request_expired,request_active;
 wire [1:0] request_timeout_cause;
 tri1 scl,sda;
 assign scl=(sl||slave_scl)?1'b0:1'bz;
 assign sda=(dl||slave_sda)?1'b0:1'bz;
 reg [7:0] commands[0:16639],responses[0:16639],digests[0:319],bad_nonce[0:3];
 reg [7:0] probe_addr=8'hxx;
 wire [15:0] probe_data;
 integer word_index;
 firm_serial_rom rom_probe(.addr(probe_addr),.data(probe_data));
 integer bank=0,seen=0,writes=0,completed=0,current_fault=0,tx_records=0;
 reg stop_seen=0,terminal=0;
 reg [7:0] status=0,error=0,consumed=0;
 wire [7:0] tt_ui={5'd0,present,1'b0,rx};
 wire [7:0] tt_uo,tt_out,tt_oe;
 tt_um_derrykervin_firm_card_01 dut(.ui_in(tt_ui),.uo_out(tt_uo),.uio_in({6'd0,scl,sda}),.uio_out(tt_out),.uio_oe(tt_oe),.ena(ena),.clk(clk),.rst_n(card_rst_n));
 assign tx=tt_uo[0];assign halted=tt_uo[4];assign busy=tt_out[3];assign ok=tt_out[4];
 assign sl=tt_oe[1] && !tt_out[1];assign dl=tt_oe[0] && !tt_out[0];
 assign request_expired=tt_out[5];assign request_timeout_cause=tt_out[7:6];
 assign request_active=dut.core.request_active;assign rom_addr=dut.core.rom_addr;
 assign pc=dut.core.debug_pc;assign r0=dut.core.debug_r0;assign gpio=dut.core.gpio_out;
 always @(posedge clk)begin
  if(tt_out[1:0]!==0)$fatal(1,"TT open drain data driven high");
  if(!ena && (tt_oe!==0 || tt_uo!==8'h09))$fatal(1,"TT disabled pin safety");
 end
 defparam dut.core.UART_CLKS_PER_BIT=CPB;
 defparam dut.core.DIV=DIV;
 defparam dut.core.REQUEST_FRAME=640*CPB;
 defparam dut.core.WAKE_LOW_CYCLES=7;
 defparam dut.core.WAKE_HIGH_CYCLES=13;
 defparam dut.core.EXEC_WAIT_CYCLES=17;
 defparam dut.core.POLL_CYCLES=80;
 defparam dut.core.MAX_READ_ATTEMPTS=3;
 defparam dut.core.BYTE_TIMEOUT=400+100*DIV;
 defparam dut.core.BUS_TIMEOUT=SERIAL_DRAIN+20000+3000*DIV;
 defparam dut.core.READ_TIMEOUT=SERIAL_DRAIN+30000+4000*DIV;
 defparam dut.core.PRODUCER_TIMEOUT=200000+20000*DIV;
 defparam dut.core.COMMAND_TIMEOUT=SERIAL_DRAIN+100000+10000*DIV;
 defparam dut.core.WAKE_TIMEOUT=30000+4000*DIV;
 defparam dut.core.TOTAL_TIMEOUT=TOTAL;
 always @(posedge clk)if(rst_n && busy && ok)$fatal(1,"card committed before session complete");
 // No test controls or diagnostics are implemented on the legacy bus.
 always @(posedge clk) if(rst_n && dut.core.core.io_we && dut.core.core.io_addr!=8'h11)
  $fatal(1,"serial unexpected legacy write");
 always @(posedge sda) begin #1;if(scl && rst_n && dut.core.core.processor.endpoint.session.state==4) stop_seen=1;end
 task read_uart;
  output [7:0] v;integer j;
  begin
   @(negedge tx);repeat(CPB/2) @(posedge clk);#1;
   if(tx!==0) $fatal(1,"serial UART start");
   for(j=0;j<8;j=j+1) begin repeat(CPB) @(posedge clk);#1;v[j]=tx;end
   repeat(CPB) @(posedge clk);#1;if(tx!==1) $fatal(1,"serial UART stop");
   $display("UART_RX %02h",v);
  end
 endtask
 task records;
  reg [7:0] tag,value;
  begin : decode
   forever begin
    read_uart(tag);
    if(tag==8'hd0) begin
     read_uart(value);
     if(seen>=(identity_mode?84:64) || value!==(identity_mode ? (seen<20 ? responses[bank+1+seen] : responses[bank+513+seen-20]) : responses[bank+897+seen])) $fatal(1,"serial provisional byte mismatch");
     seen=seen+1;tx_records=tx_records+1;
    end else if(tag==8'hf0) begin
     read_uart(status);read_uart(error);read_uart(consumed);terminal=1;disable decode;
    end else $fatal(1,"serial record tag mismatch");
   end
  end
 endtask
    task wait_start;
        begin : search
            forever begin @(negedge sda);if(scl===1'b1) disable search;end
        end
    endtask
    task receive_byte;
        input [7:0] expected;input ack;reg [7:0] value;integer b;
        begin
            for(b=7;b>=0;b=b-1) begin @(posedge scl);value[b]=sda;end
            if(value!==expected) $fatal(1,"CPU endpoint command wire byte got=%h expected=%h",value,expected);
            @(negedge scl);slave_sda=ack;@(posedge scl);@(negedge scl);slave_sda=0;
        end
    endtask
    task send_byte;
        input [7:0] value;input ack;integer b;
        begin
            slave_sda=!value[7];
            for(b=7;b>=0;b=b-1) begin @(posedge scl);@(negedge scl);
                if(b>0) slave_sda=!value[b-1];else slave_sda=0;
            end
            @(posedge scl);#1;if(sda!==!ack) $fatal(1,"CPU endpoint response ACK/NACK");@(negedge scl);
        end
    endtask
    function [15:0] next_crc;
      input [15:0] prior;input [7:0] value;integer k;reg [15:0] c;
      begin c=prior;for(k=0;k<8;k=k+1) c=(c[15]^value[k])?{c[14:0],1'b0}^16'h8005:{c[14:0],1'b0};next_crc=c;end
    endfunction
    task device;
        input integer fault;integer stage,offset,length,count,attempt,j;reg nack;reg [7:0] sent;reg [15:0] response_crc;
        begin
            wait(dut.core.core.processor.endpoint.session.wake_engine.state==2);@(posedge sda);
            begin : wake_response
                for(attempt=0;attempt<3;attempt=attempt+1) begin
                    wait_start;@(negedge scl);nack=(fault==12 && attempt==0);receive_byte(8'hc1,!nack);
                    if(!nack) begin
                        send_byte(4,1);send_byte(fault==1?8'h00:8'h11,1);
                        send_byte(fault==1?8'h03:8'h33,1);send_byte(fault==1?8'h40:8'h43,0);
                        disable wake_response;
                    end
                end
            end
            for(stage=0;stage<(identity_mode?5:13);stage=stage+1) begin
                offset=bank+128*stage;length=commands[offset];count=responses[offset];
                wait_start;@(negedge scl);writes=writes+1;receive_byte(8'hc0,1);receive_byte(3,1);
                for(j=0;j<length;j=j+1) receive_byte(commands[offset+j],1);
                begin : command_response
                    for(attempt=0;attempt<3;attempt=attempt+1) begin
                        wait_start;stop_seen=0;@(negedge scl);
                        nack=(fault==2 && stage==7 && attempt==0);receive_byte(8'hc1,!nack);
                        if(!nack) begin
                            for(j=0;j<count;j=j+1) begin
                                if(fault==3 && stage==6) send_byte(bad_nonce[j],j!=count-1);
                                else begin
                                      sent=responses[offset+j];
                                      if(j>0 && j<count-2)begin
                                        if((fault==20 || fault==23) && stage==8 && j==2)sent=sent^1;
                                        if((fault==21 || fault==24) && stage==12 && j==64)sent=sent^1;
                                        if(fault==22 && stage==0 && j==25)sent=sent^1;
                                        if(fault==25 && stage==3 && j==5)sent=8'h13;
                                        if(fault==26 && stage==2 && j==25)sent=sent|4;
                                        if(fault==27 && (stage==0 || stage==8) && (j<=4 || (j>=9 && j<=13)))sent=0;
                                        if(fault==28 && (stage==0 || stage==8) && j==20)sent=8'h08;
                                      end
                                      if(j==0)response_crc=0;
                                      if(j<count-2)response_crc=next_crc(response_crc,sent);
                                      else sent=j==count-2?response_crc[7:0]:response_crc[15:8];
                                      if(((fault==4 && stage==7)||(fault==15 && stage==5)||(fault==30 && stage==0)||(fault==31 && stage==4)) && j==count-1)sent=sent^1;
                                      send_byte(sent,j!=count-1);
                                    end
                            end
                            if(fault==5 && stage==7) slave_scl=1;
                            disable command_response;
                        end
                    end
                end
            end
        end
    endtask
 task run_case;
  input integer context_id,fault,expected,fresh,enumerate;integer j,index;
  begin
   identity_mode=enumerate;index=request_number;request_number=request_number+1;
   if(fresh)begin rst_n=0;repeat(5)@(negedge clk);end
   present=1;slave_scl=0;slave_sda=0;bank=index*1664;seen=0;writes=0;
   terminal=0;status=0;error=0;consumed=0;current_fault=fault;stop_seen=0;proof_seen=0;
   @(negedge clk);rst_n=1;wait(card_ready && !reader_busy);@(negedge clk);
   fork : system_attempt
    device(fault);
    records;
    begin for(j=0;j<host_request_lengths[index];j=j+1)send_host_byte(host_requests[index*128+j]);end
    begin read_host_frame(index);wait(terminal);repeat(CPB*2)@(negedge clk);disable system_attempt;end
   join
   if(request_expired || busy || error!==expected || !status[1] || halted || frame_fault || overrun || power_fault)
    $fatal(1,"host system CARD terminal qualification");
   if(expected==0)begin
    if(proof_seen!=(identity_mode?84:64) || seen!=(identity_mode?84:64) || consumed!=(identity_mode?84:64) || writes!=(identity_mode?5:13) || !ok)
     $fatal(1,"host system successful completion");
   end else if(proof_seen!=0 || ok)$fatal(1,"host system tentative proof escaped");
   $display("RESULT IDENTITY_SYSTEM context=%0d fault=%0d status=%h tentative=%0d delivered=%0d",context_id,fault,status,seen,proof_seen);
   completed=completed+1;
   // Identical host retry returns the cached complete frame, no new CARD I2C.
   writes=0;stop_seen=0;
   fork
    begin for(j=0;j<host_request_lengths[index];j=j+1)send_host_byte(host_requests[index*128+j]);end
    read_host_frame(index);
   join
   repeat(CPB*3)@(negedge clk);
   if(writes!=0 || busy || sl || dl || reader_busy)$fatal(1,"host retry reexecuted CARD");
   $display("PASS HOST_RETRY sequence=%0d no_device_execution=1",index+1);
   completed=completed+1;
   slave_scl=0;slave_sda=0;
  end
 endtask
 initial begin repeat(120000000) @(posedge clk);$fatal(1,"serial watchdog");end
 initial begin
  host_capture_fd=$fopen("host_uart_frames.hex","w");if(host_capture_fd==0)$fatal(1,"host capture open");
  $readmemh("host_request_lengths.hex",host_request_lengths);
  $readmemh("host_requests.hex",host_requests);$readmemh("host_expected.hex",host_expected);$readmemh("host_lengths.hex",host_lengths);
  $readmemh("serial_secure_rom.hex",rom,0,255);
  $readmemh("session_commands.hex",commands,0,16639);$readmemh("session_responses.hex",responses,0,16639);
  $readmemh("session_digests.hex",digests,0,319);$readmemh("bad_nonce.hex",bad_nonce,0,3);
  for(word_index=0;word_index<256;word_index=word_index+1) begin
   #1;probe_addr=word_index;#1;
   if(probe_data!==rom[word_index]) $fatal(1,"budget ROM word mismatch");
  end
  @(negedge clk);ena=0;repeat(4)@(negedge clk);
  if(tt_oe!==0 || tt_uo!==8'h09)$fatal(1,"TT ENA idle isolation");
  @(negedge clk);ena=1;
  run_case(0,0,0,1,1);run_case(0,0,0,0,0);
  run_case(1,0,0,0,1);run_case(1,0,0,0,0);
  run_case(0,31,7,0,1);run_case(0,0,0,0,1);
  run_case(1,20,7,0,0);run_case(1,0,0,0,1);
  run_case(0,27,7,0,1);run_case(0,0,0,0,0);
  $display("PASS identity TT system CPB=%0d DIV=%0d completed=%0d ROM=256",CPB,DIV,completed);$fclose(host_capture_fd);$finish;
 end
endmodule
