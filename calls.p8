pico-8 cartridge // http://www.pico-8.com
version 22
__lua__
-- birdsong generator
-- (c) 2020 john doty
--
-- generates random birdsong.
--

------------------------------
-- song
------------------------------
function lerp(a,b,t)
 return a+(b-a)*t
end

function gen_chirp(i)
 local base=0x3200+(68*i)
 
 local cl=rnd(8)+16
 for i=0,63,1 do
  poke(base+i,0)
 end

 -- set speed to 1.
 poke(base+65,1) 
   
 -- set pitches. 
 -- it sounds better (i found) 
 -- if you lerp over 4 tones 
 -- between points. 
 -- discontinuities sound gross,
 -- but you still want the pitch
 -- changes quick.
 local old=rnd(8)+56
 for i=0,cl,4 do
  local new=rnd(8)+56
  for j=0,3 do
   local addr=base+(i+j)*2
   local pitch=lerp(old,new,j/4)
   poke2(addr, 0x0a00|pitch)
  end
  old=new
 end
end

song={}
function gen_song()
 local notes=ceil(rnd(4))
 for i=0,notes-1 do
  gen_chirp(i)
 end
 
 song={}
 local sl=ceil(rnd(3))
 for i=1,sl do
  add(song, flr(rnd(notes)))
 end
 
 -- these are in frames, or 1/30
 -- of a second.
 note_delay=rnd(5)+2
end

function update_song()
 if stat(20)==-1 then
  -- no note, where are we?   
  delay-=1
  if delay<0 then
   if note_idx<#song then
    note_idx+=1
    sfx(song[note_idx])
     
    -- when the note is done
    -- wait this amount of time
    delay=note_delay
    pd=delay
   else
    playing=false
    note_idx=0
   end
  end
 end
end

-------------------------------
-- bird
-------------------------------
bird_colors={10,9,4,8}
bird_min=96
bird_max=127
bird={
 {{-2,0},
  {-2,-3},
  {0,0},
  {0,-4},
  {0,0},
  {2,-3},
  {2,0}},
 {{-5,-3},
  {-2,-3},
  {0,0},
  {2,-3},
  {5,-3}},
 {{-5,-4},
  {-2,-3},
  {0,0},
  {2,-3},
  {5,-4}},
 {{-5,-1},
  {-2,-3},
  {0,0},
  {2,-3},
  {5,-1}},
}

function init_bird()
 bird_x=110 bird_y=1
 bird_state="incoming"
 bird_frame=3
 bird_color=bird_colors[flr(rnd(#bird_colors))+1]
 gen_song()
end

function move_bird(ydir)
 bird_y+=ydir*2
 bird_x+=rnd(4)-2
 if bird_x>bird_max then bird_x=bird_max end
 if bird_x<bird_min then bird_x=bird_min end
 
 bird_frame+=1
	if bird_frame>#bird then
	 bird_frame=2
	end
end

function update_bird()
 if bird_state=="incoming" then
  move_bird(1)
  if bird_y>=96 then
   bird_y=96
   bird_state="sitting"
	  playing=true
  end
 elseif bird_state=="sitting" then
  bird_frame=1
 elseif bird_state=="leaving" then
  move_bird(-1)
  if bird_y<0 then
   bird_y=0
   init_bird()
  end
 end
end

function draw_bird()
 rectfill(
  bird_min-5,0,
  bird_max,96,
  12)
 rectfill(
  bird_min-5,96,
  bird_max,128,
  11)

 local x,y=bird_x,bird_y
 color(bird_color)
 -- wings
 local b=bird[bird_frame]
 line(x+b[1][1],y+b[1][2],
      x+b[2][1],y+b[2][2])
 for i=3,#b do
  line(x+b[i][1],y+b[i][2])
 end
end

-------------------------------
-- yada
-------------------------------
function _init()
 init_bird()
 note_idx=0
 playing=false
 delay=0
end

function _update()
 if btnp(🅾️) then
  playing=not playing
 end
 if btnp(❎) then
  note_idx=0
  bird_state="leaving"
 end
 if playing then
  update_song()
 end
 update_bird()
end

function _draw()
 cls(0)
 draw_bird()
 draw_song()
end

function draw_song()
 local i,ni
 
 for ni=1,#song do
  local s=song[ni]
	 local base=0x3200+(68*s)
  for i=0,31 do
   local pitch=peek(base+(i*2))
   if pitch>0 then
    local x=(ni-1)*32+i
    local c=1
    if ni==note_idx and 
       i==stat(20) then
     c=7
    end
    line(x,96,x,96-pitch,c)
    pset(x,96-pitch,bird_color)
   end
  end
 end
end
__gfx__
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00700700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00077000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00077000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00700700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__sfx__
000100003305034050350503405032050300502c05028050230501d0501905016050140501305012050120501305014050180501e050250502b050300503305034050320502f0502805022050210502305024050
000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000100001e00000000370503c0503c00000000000000000000000380503c05000000000003805035050380503505038050350500000000000000003800013000380503c050000000000000000000000000000000
000900003c050000003c05000000000000000000000000003c0503205032000320003205000000000000000032050000000000000000000000000000000000000000000000000000000000000000000000000000
00080000300503c0500000000000000003005030050300503c0502c0003c00030000230003c000300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00100720070500a0500c0500f050110501605016050180501b0501b0501d050160501605016050180501b0501f0501f05022050220502705029050270502705027050220501f0502205022050220502405027050
