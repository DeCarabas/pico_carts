pico-8 cartridge // http://www.pico-8.com
version 18
__lua__
-- robo gardening game
-- (c) 2020 john doty
-- goals: new plants
-- goals: more garden
-- goals: storylets?
-- todo: zelda rock sprites
px=1 py=1 d=0
spd=0.125 walking=false
idle_time=0

menu_mode=false
menu_sel=1
menu_items={}

-- days are 24 hrs long
-- this is how much of an hr we
-- tick every frame. (tweak for
-- fun!)
hour_inc=0.0009*200
hour=7
day=0

-- the map is divided into 4 
-- regions, horizontally.
-- x=[0,32)   base layer
-- x=[32,64)  item sprite layer
-- x=[64,96)  ?? water level?
-- x=[96,128) ??
--
-- (each region is further 
-- divided into 4 16x16 
-- screens.)

function _init() 
 tx = px ty = py
 -- init the item sprite layer
 for i=1,20 do
  mset(32+flr(rnd(16)),flr(rnd(16)),65)
 end
end

function open_item_menu()
 menu_mode=true
 menu_sel=item_sel
 menu_items={}
 for it in all(items) do
  add(menu_items,it.name)
 end
end

function looking_at()
 if d==0 then return {x=px-1,y=py} end --left 
 if d==1 then return {x=px+1,y=py} end --right
 if d==2 then return {x=px,y=py+1} end --down
 return {x=px,y=py-1} --up
end

-- flags:
-- 0: collision
-- 1: cannot plant
--
function map_flag(x,y,f)
 return fget(mget(x,y),f) or
        fget(mget(x+32,y),f)
end

function use_thing()
 local item=items[item_sel]
 if item.fn~=nil then
  local tgt=looking_at()
  item.fn(item,tgt.x,tgt.y)
 end
end

function collide(px,py,tx,ty)
 if tx~=px then
  if ty~=py then
   if map_flag(tx,ty,0) then return true end
  end
  if map_flag(tx,py,0) then return true end
 end
 if ty~=py then
  if map_flag(px,ty,0) then return true end
 end
 return false
end

buzz=0

function update_walk()
 if buzz > 0 then buzz -= 0.75 end

 if btnp(⬅️) then tx = flr(px-1); d=0 end    
 if btnp(➡️) then tx = ceil(px+1); d=1 end
 if btnp(⬇️) then ty = flr(py+1); d=2 end
 if btnp(⬆️) then ty = ceil(py-1); d=3 end
 if tx < 0  then buzz=3 tx = 0  end
 if tx > 15 then buzz=3 tx = 15 end
 if ty < 0  then buzz=3 ty = 0  end
 if ty > 15 then buzz=3 ty = 15 end
 if collide(px,py,tx,ty) then
  tx=px ty=py
 end
 if px > tx then px -= spd end
 if px < tx then px += spd end
 if py > ty then py -= spd end
 if py < ty then py += spd end
	walking=not (tx == px and ty == py)
 if walking then idle_time=0 end
 
 if btnp(❎) then open_item_menu() end
 if btnp(🅾️) and not walking then 
  use_thing()
  idle_time=0
 end

 hour+=hour_inc
 if hour>24 then day+=1 hour-=24 end
 
 idle_time+=0.0333
end

function update_menu()
 if btnp(⬇️) then menu_sel+=1 end
 if btnp(⬆️) then menu_sel-=1 end
 if btnp(❎) then menu_mode=false end
 if btnp(🅾️) then item_sel=menu_sel; menu_mode=false end
 if menu_sel < 1 then menu_sel = 1 end
 if menu_sel > #menu_items then menu_sel=#menu_items end
end

function _update()
 update_plants()
 if menu_mode then
  update_menu()
 else
  update_walk()
 end
end

function draw_box(x, y, w, h)
 palt(0, false)
 palt(12, true)
 spr(128,x,y)
 for ix=1,w do
  spr(129,x+(ix*8),y)
 end
 local xr = x+(w+1)*8
 spr(128,xr,y,1,1,true)
 for iy=1,h do
  spr(130,x, y+(iy*8),1,1,false)
  spr(130,xr,y+(iy*8),1,1,true)
 end
 local yb = y+(h+1)*8
 spr(128,x,yb,1,1,false,true)
 for ix=1,w do
  spr(129,x+(ix*8),yb,1,1,false,true)
 end
 spr(128,xr,yb,1,1,true,true)
 rectfill(x+8,y+8,xr,yb,0)
 palt()
end

function draw_menu(items, selection)
 draw_box(64,8,5,4)
 local lx=71
 local ly=16
 for i=1,#items do
  if selection == i then
   print(">",lx,ly,7)
  end
  print(items[i],lx+6,ly,7)
  ly += 6
 end
end

moon_phases={134,135,136,137,138,139,138,137,136,135}
function moon()
 -- 3 days in a phase
 -- 10 moon phases in a cycle
 local phase=flr(day/3)%10
 return {
  sprite=moon_phases[phase+1],
  flipped=phase>5
 } 
end

function draw_time()
 -- daytime is 06:00-18:00
 -- night is 18:00-06:00
 -- where are we?
 local bg=12
 local fg=9
 local sp=133
 local fl=false

 local is_day=true 
 local frc
 if hour>=6 and hour<18 then
  frc=(hour-6)/12
 elseif hour>=18 then
  frc=(hour-18)/12
  is_day=false
 else
  frc=(hour+6)/12
  is_day=false
 end

 if not is_day then
  local mun=moon()
  sp=mun.sprite
  fl=mun.flipped
  bg=0 fg=5
 end
 
 --print("??? "..sp)
 rectfill(16,7,110,18,bg)
 rect(16,7,110,18,fg)
 spr(sp,16+(87*frc),9,1,1,fl)
end

function draw_item()
 draw_box(88,96,2,1) 
 print("🅾️",95,106,7)
 spr(items[item_sel].icon,104,104)
end

function world_to_screen(wx,wy)
 return {x=wx*8+4,y=wy*8+4}
end

function draw_map()
 local ofx=0
 local ofy=0
 if buzz>0 then 
  ofy+=cos(buzz) 
  ofx+=sin(buzz) 
 end
	map( 0,0,ofx+0,ofy+0,16,16) -- base
	map(32,0,ofx+0,ofy+0,16,16) -- item
end


function _draw()
	--cls(0)

 if (hour>=18 and hour<20) or 
    (hour>=4 and hour<6) then
  dark(1)
 elseif hour>=20 or hour<4 then
  dark(2)
 end
	
	draw_map()
	
 palt(0, false)
 palt(12, true)
 if d == 2 then idx=1; fl=false end 
 if d == 3 then idx=9; fl=false end
 if d == 1 then idx=5; fl=false end
 if d == 0 then idx=5; fl=true end
 if (flr(time() * 4) % 2) == 0 then idx += 2 end
 local sc=world_to_screen(px,py)
 spr(idx,sc.x-8,sc.y-12,2,2,fl) 
 pal()
 
 --rectfill(sc.x-4,sc.y-4,sc.x+4,sc.y+4,7) 
 --local tc=looking_at()
 --sc=world_to_screen(tc.x,tc.y)
 --rectfill(sc.x-4,sc.y-4,sc.x+4,sc.y+4,10)
  
 -- print("x "..x.." y "..y)
 if menu_mode then
  draw_menu(menu_items,menu_sel)
 elseif idle_time>1 then
  draw_item()
  draw_time()
 end
end
-->8
-- plants and items
grass={
 name="grass",
 rate=0.025,
 stages={144,145,146,147}
}
mum={
 name="mum",
 rate=0.025,
 stages={160,161,162,163}
}

plant_classes={grass,mum}

-- init the reverse-lookup table
-- for the plant data.
plant_spr={}
for p in all(plant_classes) do
 for s in all(p.stages) do
  plant_spr[s]=p
 end
end 

plants={}

function update_plants()
 for p in all(plants) do
  local class=p.cls
  local age=p.age
  if age < #class.stages then
   -- update the age
   local new_age=age+class.rate
   if flr(new_age)~=flr(age) then
    mset(
     p.x+32,
     p.y,
     class.stages[flr(new_age)])
   end
   p.age=new_age
  end  
 end
end

function i_plant(item,tx,ty)
 local p=item.plant
 if not map_flag(tx,ty,1) then
  add(
   plants,
   {age=1,x=tx,y=ty,cls=p})
  mset(tx+32,ty,p.stages[1])
 end
end

function i_shovel(item,tx,ty)
end

items={
 -- pick axe hoe water
 -- or just shovel
 --{icon=131,name="shovel",fn=i_shovel},
 --{icon=132,name="carrot"},
 {icon=147,name="grass",fn=i_plant,plant=grass},
 {icon=163,name="mum",fn=i_plant,plant=mum},
}
item_sel=1

-->8
-- fx
dark_map={
 0, --0
 0, --1
 1, --2
 5, --3
 5, --4
 2, --5
 5, --6
 6, --7
 5, --8
 8, --9
 9, --10
 3, --11
 13,--12
 1, --13
 13,--14
 14 --15
}

function dark(n)
 local dm=dark_map
 for i=0,15 do
  local tgt=i
  for j=1,n do
   tgt=dm[tgt+1]
  end
  pal(i,tgt)
 end
end

__gfx__
0000000000cccccccccccc0000cccccccccccc00ccc0ccccccccccccccc0cccccccccccc00cccccccccccc0000cccccccccccc00000000000000000000000000
00000000070c00000000c070070c00000000c07000070c00000ccccc00070c00000ccccc070c00000000c070070c00000000c070000000000000000000000000
00700700c07007777770070cc07007777770070c070700e007700ccc070700e007700cccc07007777770070cc07007777770070c000000000000000000000000
00077000cc007000000700cccc007000000700ccc0700ee0000770ccc0700ee0000770cccc070000000070cccc070000000070cc000000000000000000000000
00077000c00000000000000cc00000000000000ccc00eee00000770ccc00eee00000770cc00070000007000cc00070000007000c000000000000000000000000
007007000e7000e00e0007e00ee000e00e000ee0cc0ee00e0000070ccc0ee00e0000070c07700700007007700770070000700770000000000000000000000000
000000000e7000e00e0007e00ee000e00e000ee0cc0e0770e000070ccc0e0770e000070c07700077770007700770007777000770000000000000000000000000
000000000ee0000000000ee00ee0000000000ee0cc0070070000070ccc0070070000070c07700070070007700770007007000770000000000000000000000000
c00cc00c0ee0770000770ee00ee0770000770ee0cc0e0070e700000ccc0e0070e700000c0ee0700000070ee00ee0700000070ee0000000000000000000000000
0ee00ee000007777777700000000777777770000cc0ee070e770000ccc0ee070e770000c000070eeee070000000070eeee070000000000000000000000000000
0e0ee0e000007777777700000ee0777777770ee0cc0ee070e777770ccc0ee0700777770c0ee0e0eeee0e0ee00000e0eeee0e0000000000000000000000000000
0e0e5e0007707777777707700000777777770000cc0ee070e777770ccc0ee0070007770c0000ee0000ee00000ee0ee0000ee0ee0000000000000000000000000
0e05e0cc0ee0077777700ee00ee0077777700ee0ccc00777077770ccccc00000770070cc0ee00eeeeee00ee00ee00eeeeee00ee0000000000000000000000000
c000000c0ee0000000000ee00ee0000000000ee0cc00777700000ccccc00000777700ccc0ee0000000000ee00ee0000000000ee0000000000000000000000000
0ee0eee0c000eee00eee000c0ee0e00ee00e0ee0cc0070070e0e0ccccc0e000700700ccc0ee0e00ee00e0ee0c000eee00eee000c000000000000000000000000
00000000ccc0000000000cccc00000000000000ccc000c0000000ccccc000c0000000cccc00000000000000cccc0000000000ccc000000000000000000000000
c00cc00ccc000cccccc000cccc000cccccc000ccc0000cccccc0000c000000000000000000000000000000000000000000000000000000000000000000000000
0ee00ee0c06660cccc06660cc06660cccc06660cc06660000006660c000000000000000000000000000000000000000000000000000000000000000000000000
0e0ee0e006660500005066600666050000506660cc066666666660cc000000000000000000000000000000000000000000000000000000000000000000000000
0e0e5e0006660066660066600666006666006660ccc0666666660ccc000000000000000000000000000000000000000000000000000000000000000000000000
00e5e0cc06660676676066600666067667606660cc060066660060cc000000000000000000000000000000000000000000000000000000000000000000000000
c000000c06660706607066600666070660706660c00770666607700c000000000000000000000000000000000000000000000000000000000000000000000000
0eee0ee006660666666066600666066666606660c07777777777770c000000000000000000000000000000000000000000000000000000000000000000000000
00000000c06000666600060cc06000666600060ccc0077700777000c000000000000000000000000000000000000000000000000000000000000000000000000
00000000cc006067760600cccc006067760600ccc006077777700600000000000000000000000000000000000000000000000000000000000000000000000000
00000000ccc0660000660cccccc0660000660ccc0660600000066060000000000000000000000000000000000000000000000000000000000000000000000000
00000000cc066605506660cccc066605506660cc060006666666000c000000000000000000000000000000000000000000000000000000000000000000000000
00000000cc066605506660cccc066605506660cc06607000000070cc000000000000000000000000000000000000000000000000000000000000000000000000
00000000c00066055066000cc00066055066000cc000000777770ccc000000000000000000000000000000000000000000000000000000000000000000000000
0000000006660060060066600666006006006660ccc0660000000ccc000000000000000000000000000000000000000000000000000000000000000000000000
0000000006666660066666600000000006666660cccc000666660ccc000000000000000000000000000000000000000000000000000000000000000000000000
00000000c000000cc000000cccccccccc000000ccccccc000000cccc000000000000000000000000000000000000000000000000000000000000000000000000
44444444056666000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
45444444665556600000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
44444544666566660000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
44444444665566660000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
44444444556655650000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
44445444666565650000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
44544444065566500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
44444444005555000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
44576544444444444457654400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
45576544455555544555555400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
44576544457776554577765500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
44576544457776574577765700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
44576544455555564555555600000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
44576544455765554577765500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
44576544455765544577765400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
44576544445765444555555400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
44576544444444444457654400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
45555554455555544555555400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
45777654557776545577765400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
45777654757776547577765400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
45555554655555546555555400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
45576554555765545577765400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
45576554455765544577765400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
44576544445765444555555400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
44444444444444440000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
45444444455555540000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
55555555557776550000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
77777777757776570000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
66666666655555560000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
55555555557776550000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
44544444457776540000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
44444444455555540000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
cccccccccccccccccc53350000000500000000000000000000555500005555000055550000555500005555000055550000700000000000000000000000000000
cccccccccccccccccc53350000000050000005000990909005777750057777500577755005777550057755500555555000600000000000000000000000000000
cccc555555555555cc5335000000050500003350009999905777777557777755577775555777555557755555555555550c5a0b00000000000000000000000000
ccc5533333333333cc5335000000500000099335099aa9005777777557777775577775555777555557755555555555550d2903f0000000000000000000000000
cc55333333333333cc5335000065000000998053009aa990577777755777777557777555577755555775555555555555011405e0000000000000000000000000
cc53335555555555cc533500066650000998003009999900577777755777775557777555577755555775555555555555000500d0000000000000000000000000
cc53350000000000cc53350067650000998000000909099005777750057777500577755005777550057755500555555000000020000000000000000000000000
cc53350000000000cc53350076500000980000000000000000555500005555000055550000555500005555000055550000000010000000000000000000000000
000000000000000000000000b0000b00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000003b00b3bb000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000b0b00b0b3b30000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000b0b0003b30b30000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000b0000b30b00b0b3b300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000b000b00b0b30b00b0b3b30b000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0b00b0000b300b300b300bb00bb3b3b0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00b0b0bb03b0b3b00b30b3b00bb3b3b0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000ddd00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000ddd00000dad0ddd0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000ddd00000ddd0dad0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000b3000000b300ddd0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000003b0000003dd0dd00ddd0300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
030000000300000003dd0dd00dad03b0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000030b3000030b3000dddb300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00300300003003000030030000300300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__gff__
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000030000000000000000000000000000030303000000000000000000000000000303030000000000000000000000000003030000000000000000000000000000
0000000000000000000000000000000002020202000000000000000000000000020202020000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__map__
4040404040404040404040404040404000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
4040404040404040404040404040404000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
4040404040404040404040404040404000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
4040404040404040404040404040404000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
4040404040404040404040404040404000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
4040404040404040404040404040404042000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
4040404040404040404040404040404042000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
4040404040404040404040404040404000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
4040404040404040404040404040404000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
4040404040404040404040404040404000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
4040404040404040404040404040404000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
4040404040404040404040404040404000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
4040404040404040404040404040404000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
4040404040404040404040404040404000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
4040404040404040404040404040404000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
4040404040404040404040404040404000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
