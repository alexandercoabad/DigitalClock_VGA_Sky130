/* * Retro Digital Clock & Date Display
 * [0]=12h/24h, [7]=Hold for Date
 * Clock Mode: [1,2]=Hour +/-, [3,4]=Min +/-, [5]=Sec Sync
 * Date Mode:  [1,2]=Month +/-, [3,4]=Day +/-, [5,6]=Year +/-
 */

`default_nettype none

module tt_um_digitalclock(
  input  wire [7:0] ui_in,    
  output wire [7:0] uo_out,   
  input  wire [7:0] uio_in,   
  output wire [7:0] uio_out,  
  output wire [7:0] uio_oe,   
  input  wire ena,            
  input  wire clk,            
  input  wire rst_n           
);

  wire hsync, vsync, video_active;
  wire [9:0] pix_x, pix_y;
  reg [1:0] R, G, B;

  assign uo_out = {hsync, B[0], G[0], R[0], vsync, B[1], G[1], R[1]};
  assign uio_out = 0; assign uio_oe = 0;

  hvsync_generator hvsync_gen(
    .clk(clk), .reset(~rst_n), .hsync(hsync), .vsync(vsync),
    .display_on(video_active), .hpos(pix_x), .vpos(pix_y)
  );

  // --- Registers ---
  reg [4:0] h_c; reg [5:0] m_c, s_c;
  reg [3:0] month; reg [4:0] day; reg [6:0] year;
  reg [24:0] tick_c;
  reg [7:0] last_btns;

  localparam CLOCK_FREQ = 10000000; 
  wire mode_date  = ui_in[7];

  // --- Leap Year & Month Limits ---
  wire is_leap = (year[1:0] == 2'b00); 
  wire [4:0] max_days = (month == 4 || month == 6 || month == 9 || month == 11) ? 5'd30 :
                        (month == 2) ? (is_leap ? 5'd29 : 5'd28) : 5'd31;

  always @(posedge clk or negedge rst_n) begin
    if (~rst_n) begin
      {tick_c, s_c, m_c, h_c} <= {25'd0, 6'd0, 6'd0, 5'd12};
      {month, day, year} <= {4'd12, 5'd29, 7'd25}; 
      last_btns <= 0;
    end else begin
      last_btns <= ui_in;

      // --- CLOCK & DATE ROLLOVERS ---
      if (tick_c >= CLOCK_FREQ) begin
        tick_c <= 0;
        if (s_c == 59) begin 
            s_c <= 0; 
            if (m_c == 59) begin 
                m_c <= 0; 
                if (h_c == 23) begin
                    h_c <= 0;
                    if (day >= max_days) begin 
                        day <= 1; 
                        if (month == 12) begin month <= 1; year <= (year == 99) ? 0 : year + 1; end 
                        else month <= month + 1; 
                    end else day <= day + 1;
                end else h_c <= h_c + 1;
            end else m_c <= m_c + 1; 
        end else s_c <= s_c + 1;
      end else tick_c <= tick_c + 1;

      // --- INTERFACE LOGIC ---
      if (mode_date) begin
          // Month +/- (Pins 1 & 2)
          if (ui_in[1] && !last_btns[1]) month <= (month == 12) ? 1 : month + 1;
          if (ui_in[2] && !last_btns[2]) month <= (month == 1) ? 12 : month - 1;
          // Day +/- (Pins 3 & 4)
          if (ui_in[3] && !last_btns[3]) day <= (day >= max_days) ? 1 : day + 1;
          if (ui_in[4] && !last_btns[4]) day <= (day <= 1) ? max_days : day - 1;
          // Year +/- (Pins 5 & 6)
          if (ui_in[5] && !last_btns[5]) year <= (year == 99) ? 0 : year + 1;
          if (ui_in[6] && !last_btns[6]) year <= (year == 0) ? 99 : year - 1;
      end else begin
          // Clock Mode Controls
          if (ui_in[5] && !last_btns[5]) {s_c, tick_c} <= 0; 
          if (ui_in[1] && !last_btns[1]) h_c <= (h_c == 23) ? 0 : h_c + 1;
          if (ui_in[2] && !last_btns[2]) h_c <= (h_c == 0) ? 23 : h_c - 1;
          if (ui_in[3] && !last_btns[3]) m_c <= (m_c == 59) ? 0 : m_c + 1;
          if (ui_in[4] && !last_btns[4]) m_c <= (m_c == 0) ? 59 : m_c - 1;
      end
    end
  end

  // --- Display Multiplexing ---
  wire [6:0] val1 = mode_date ? {3'd0, month} : {2'd0, h_c};
  wire [5:0] val2 = mode_date ? day[5:0] : m_c;
  wire [6:0] val3 = mode_date ? year : {1'b0, s_c};
  
  wire is_12h = ui_in[0] && !mode_date;
  wire is_pm  = (val1[4:0] >= 12) && !mode_date;
  wire [4:0] disp_h = (is_12h) ? ((val1[4:0] == 0) ? 5'd12 : (val1[4:0] > 12) ? val1[4:0] - 5'd12 : val1[4:0]) : val1[4:0];
  wire hide_tens = (is_12h && disp_h < 10) || (mode_date && month < 10);

  // ... (draw_digit function remains the same) ...

  function draw_digit(input [3:0] val, input [9:0] x, input [9:0] y, input [9:0] px, input [9:0] py);
    reg a,b,c,d,e,f,g;
    begin
      a=(val!=1 && val!=4); b=(val!=5 && val!=6); c=(val!=2);
      d=(val!=1 && val!=4 && val!=7); e=(val==0||val==2||val==6||val==8);
      f=(val!=1 && val!=2 && val!=3 && val!=7); g=(val!=0 && val!=1 && val!=7);
      draw_digit = (a && px>=x+10 && px<x+40 && py>=y    && py<y+8)  || 
                   (b && px>=x+40 && px<x+48 && py>=y+8  && py<y+36) || 
                   (c && px>=x+40 && px<x+48 && py>=y+44 && py<y+72) || 
                   (d && px>=x+10 && px<x+40 && py>=y+72 && py<y+80) || 
                   (e && px>=x    && px<x+10 && py>=y+44 && py<y+72) || 
                   (f && px>=x    && px<x+10 && py>=y+8  && py<y+36) || 
                   (g && px>=x+10 && px<x+40 && py>=y+36 && py<y+44);   
    end
  endfunction

  wire blink = (tick_c < CLOCK_FREQ/2);

  wire digit_on = (!hide_tens && draw_digit(disp_h/10, 80, 200, pix_x, pix_y)) ||
                  draw_digit(disp_h%10, 140, 200, pix_x, pix_y) ||
                  draw_digit(val2/10, 250, 200, pix_x, pix_y) ||
                  draw_digit(val2%10, 310, 200, pix_x, pix_y) ||
                  draw_digit(val3/10, 420, 200, pix_x, pix_y) ||
                  draw_digit(val3%10, 480, 200, pix_x, pix_y) ||
                  ((blink || mode_date) && ((pix_x>=210 && pix_x<225 && ((pix_y>=220 && pix_y<235)||(pix_y>=245 && pix_y<255))) ||
                                            (pix_x>=380 && pix_x<395 && ((pix_y>=220 && pix_y<235)||(pix_y>=245 && pix_y<255))))) ||
                  (is_12h && is_pm && pix_x>=550 && pix_x<565 && pix_y>=265 && pix_y<280);

  wire border = (pix_x >= 50 && pix_x < 590 && pix_y >= 160 && pix_y < 320) && !(pix_x >= 60 && pix_x < 580 && pix_y >= 170 && pix_y < 310);
  wire scanline = (pix_y[1:0] == 2'b00);

  always @(*) begin
    if (!video_active) {R,G,B} = 0;
    else if (digit_on) {R,G,B} = mode_date ? 6'b001111 : 6'b001100; 
    else if (border) {R,G,B} = 6'b010101;
    else if (scanline && pix_x >= 60 && pix_x < 580 && pix_y >= 170 && pix_y < 310) {R,G,B} = 6'b000100;
    else {R,G,B} = 0;
  end

endmodule