pico-8 cartridge // http://www.pico-8.com
version 29
__lua__
-- robo gardening game
-- (c) 2020 john doty
-- 
-- == basic idea ==
-- you are a robot repaired and
-- rebuilt by a lop, in the 
-- hopes that you will be able
-- to help her with gardening
-- and the like.
--
-- == core game loop ==
-- - gather resources
-- - turn in resources to lop 
--   for upgrades
-- - upgrades let you do more
--   stuff
--
-- == systems ==
-- [ ] tools
--   [ ] hands
--     your fists initially grab
--     and lift but later can 
--     break stuff after upgrade
--
--     [x] *lift*
--     [ ] *crush rocks*
--         provides *gravel*     
--
--   [x] hand plow
--     kind of a till attachment
--     to the ends of your hands
--     which can turn the soil
--     and prepare it to grow.
--
--     [x] *prepare land*   
--         some plants won't
--         grow without it  
--
--   [ ] sprinkler system
--     upgrades increase water
--     capacity.
--
--     [x] *water ground*
--     [ ] tank capacity     
--
--   [ ] seed dispenser
--     upgrades increase seed
--     capacity.
--
--     [ ] *plant seeds* 
--
-- [ ] battery
-- [ ] range limiter
--
-- == events? ==
-- [ ] rain
-- [ ] earthquake
-- [ ] wind storm
-- [ ] lightning & fires
--
-- :todo: zelda rock sprites
-- :todo: walk change dir first
-- :todo: energy fn
-- :todo: save data 4b item 
--        4b qual. reduce game
--        to single screen. save
--        advances to 6a next 
--        day for simplicity.
--

-- flags: for game state
--

-- game progress
--  chapter 0: pre-intro
--  chapter 1: walking/no charge
--  chapter 2: clear field
--  chapter 3: till and plant

function new_game()
 base_x=2+flr(rnd(12))
 base_y=3+flr(rnd(8))
 chapter=0
 
 -- init the item sprite layer
 function place_rand(count, sp)
  local cnt=0
  while cnt<count do
   local x=1+flr(rnd(14))
   local y=1+flr(rnd(14))
   if x~=base_x and 
      y~=base_y and 
      not fget(mget(x,y),0) then
    mset(x+32,y,sp)
    cnt+=1
   end
  end
 end
  
 place_rand(80,147) --grass
 place_rand(80,65)  --rock
end

-- player state
function init_player()
 px=base_x py=base_y d=2
 spd=0.125 walking=false
 idle_time=0

 max_tank=100
 tank_level=max_tank
 
 max_energy=100
 energy_level=max_energy
 walk_cost=0.2
 grab_cost=1
 plow_cost=1
 water_cost=0.5
 plant_cost=0.5
 
 grabbed_item=nil
 tx=px ty=py
 
 animation=nil
 anim_index=nil
 anim_duration=nil
 anim_done=nil
end

-- menu state
function init_menu()
 menu_mode=false
 menu_sel=1
 menu_items={}
end

-- days are 24 hrs long
-- this is how much of an hr we
-- tick every frame. (tweak for
-- fun!)
function init_time()
 hour_inc=0.0036 --*100
 hour=8
 day=0
 
 recharge_rate=100*hour_inc/4
 water_rate=100*hour_inc/2
end

function init_base()
 -- the base points.
 mset(base_x-1,base_y,83)
 mset(base_x+1,base_y,83)
 mset(base_x,base_y,114)
end

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

function init_game()
 init_items() 
 init_menu()
 init_time()
 init_base()
 init_player()
 init_weather()
 init_water()
 init_penny()
end

function _init()
 load_font()
 init_fx()
 new_game()

 init_game()
 
 if chapter==0 then
  do_script(cs_intro)
 end
end

function open_item_menu()
 menu_mode=true
 menu_sel=item_sel
 menu_items=get_items()
 update_fn=update_menu
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
-- 2: grab-able
-- 3: plowable
-- 4: plowed
-- 5: wet
--
function map_flag(x,y,f)
 return fget(mget(x,y),f) or
        fget(mget(x+32,y),f)
end

function map_flag_all(x,y,f)
 return fget(mget(x,y),f) and
        fget(mget(x+32,y),f)
end

function use_thing()
 local items=get_items()
 local item=items[item_sel]
 if item.fn~=nil then
  local tgt=looking_at()
  item.fn(item,tgt.x,tgt.y)
 end
end

function animate(anim,done)
 animation=anim
 anim_done=done
 anim_index=1
 
 local frame=anim[1]
 anim_duration=frame.duration
end

function update_animation()
 if animation~=nil then
  anim_duration-=1
  if anim_duration==0 then
   anim_index+=1
   if anim_index>#animation then
    animation=nil
    anim_done()
   else
    local frame=animation[anim_index]
    anim_duration=frame.duration
   end
  end
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

buzz_time=0

function buzz()
 -- todo: sounds or something?
 buzz_time=3
end

function update_time(inc)
 if buzz_time > 0 then 
  buzz_time -= 0.75 
 end

 if (inc==nil) inc=hour_inc
 hour+=inc
 if hour>24 then 
  day+=1 
  hour-=24
  
  -- every night at midnight we
  -- dry everything out.
  for y=0,31 do
   for x=0,31 do
    local wet=mget(x,y)
    local dry=dry_map[wet]
    if dry~=nil then 
     mset(x,y,dry)
    end
   end
  end
 end
end

function update_walk()
 -- this is the core update fn
 -- of the game: what runs while
 -- you're "playing" the game.
 -- 
 -- most of the subsystems only
 -- update while you're playing,
 -- and are paused any other 
 -- time (cutscenes, etc.)
 update_time()
 update_base()
 update_plants()
 update_penny()

 if px==tx and py==ty then
  if btnp(⬅️) then tx=px-1 d=0 end
  if btnp(➡️) then tx=px+1 d=1 end
  if btnp(⬇️) then ty=py+1 d=2 end
  if btnp(⬆️) then ty=py-1 d=3 end
  if tx<1  then buzz() tx=1  end
  if tx>14 then buzz() tx=14 end
  if ty<1  then buzz() ty=1  end
  if ty>14 then buzz() ty=14 end
  if collide(px,py,tx,ty) then
   tx=flr(px) ty=flr(py)
  end
 end
 if px > tx then px -= spd end
 if px < tx then px += spd end
 if py > ty then py -= spd end
 if py < ty then py += spd end
	walking=not (tx == px and ty == py)
 if walking then
  energy_level-=walk_cost
  idle_time=0
 end
 
 if not walking then
  if btnp(❎) and 
     grabbed_item==nil then 
   open_item_menu()
  end
  if btnp(🅾️) then
   use_thing()
   idle_time=0
  end
 end
 
 if energy_level<=0 then
  -- uh oh, trouble.
  fade_out(function()
   px=base_x py=base_y d=2
   tx=px ty=py walking=false
   day+=1 hour=8
   energy_level=max_energy
   if chapter<2 then
    do_script(cs_firstcharge)
   else
    do_script(cs_nobattery)
   end
  end)
 end
 
 idle_time+=0.0333
end

function update_menu()
 if btnp(⬇️) then menu_sel+=1 end
 if btnp(⬆️) then menu_sel-=1 end
 if btnp(❎) then menu_mode=false end
 if btnp(🅾️) then item_sel=menu_sel; menu_mode=false end
 if menu_sel < 1 then menu_sel = 1 end
 if menu_sel > #menu_items then menu_sel=#menu_items end
 if not menu_mode then
  update_fn=update_walk
 end
end

update_fn=update_walk

function update_base()
 -- before penny fixes the base
 if (chapter<2) return
 
 if px==base_x and 
    py==base_y then
  tank_level=min(max_tank, tank_level+water_rate)
  energy_level=min(max_energy, energy_level+recharge_rate)
 end
end

function _update()
 update_animation()
 update_weather()

 --todo: this is kinda not how
 --we're doing this right now,
 --maybe we should modernize?
 if animation==nil then
  update_fn()
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
 local hght=max(4,1+#items)
 draw_box(64,0,6,hght)
 local lx=71
 local ly=9
 for i=1,#items do
  if selection == i then
   print(">",lx,ly,7)
  end
  spr(items[i].icon,lx+6,ly-1)
  print(items[i].name,lx+16,ly,7)
  ly += 10
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
 
 rectfill(16,2,110,11,bg)
 rect(16,2,110,11,fg)
 spr(sp,16+(87*frc),3,1,1,fl)
end

function draw_item()
 draw_box(96,104,2,1) 
 print("🅾️",103,114,7)
 local items=get_items()
 spr(items[item_sel].icon,112,112)
end

function draw_meters()
 draw_box(104,50,1,5)
 local tank_frac=(max_tank-tank_level)/max_tank
 rectfill(111,57+41*tank_frac,115,98,12)
 
 local nrg_frac=(max_energy-energy_level)/max_energy
 local nrg_color
 if nrg_frac<0.5 then
  nrg_color=11
 elseif nrg_frac<0.7 then
  nrg_color=10
 else
  nrg_color=8
 end
 rectfill(116,57+41*nrg_frac,120,98,nrg_color)
end

function world_to_screen(wx,wy)
 return {x=wx*8+4,y=wy*8+4}
end

function draw_map()
 local ofx=0
 local ofy=0
 if buzz_time>0 then 
  ofy+=cos(buzz_time) 
  ofx+=sin(buzz_time) 
 end
	map( 0,0,ofx+0,ofy+0,16,16) -- base
	map(32,0,ofx+0,ofy+0,16,16) -- item
end

function draw_player()
 local idx=1
 local fl=false

 if animation~=nil then
  local frame=animation[anim_index]
  idx=frame.frame
 elseif grabbed_item~=nil then
  idx=35
 else
  if (flr(time()*4)%2)==0 then
   idx+=2 
  end
 end
 
 --if d==2 then fl=false end 
 if     d==3 then idx+=8
 elseif d==1 then idx+=4
 elseif d==0 then idx+=4 fl=true
 end
 
 local sc=world_to_screen(px,py)

 local dx=0 local dy=-14
 if grabbed_item~=nil then
  if     d==0 then dx=-14  
  elseif d==1 then dx=6
  elseif d==2 then dx=-4
  elseif d==3 then dx=-4
  end

  if d==3 then
   spr(
    grabbed_item,
    sc.x+dx,
    sc.y+dy,
    1,1)
  end
 end

 -- draw robo.
 palt(0, false)
 palt(12, true)
 spr(idx,sc.x-8,sc.y-12,2,2,fl)
 palt()

 if grabbed_item~=nil and 
    d~=3 then
  spr(
   grabbed_item,
   sc.x+dx,
   sc.y+dy,
   1,1)
 end
end

function draw_base()
 local bsx=8*base_x
 local bsy=8*base_y

 if chapter<2 or
    px~=base_x or 
    py~=base_y then
  pal(10,6) -- no glow
 end
 
 spr(115,bsx-8,bsy)
 spr(115,bsx+8,bsy,1,1,true) 
 spr(99,bsx-8,bsy-8)
 spr(99,bsx+8,bsy-8,1,1,true)
 circ(bsx-2,bsy-8,3,1)
	circfill(bsx-2,bsy-8,2,10)
 circ(bsx+9,bsy-8,3,1)
	circfill(bsx+9,bsy-8,2,10)

 pal()
end

function sort(ks,vs)
 local swapped=true
 while swapped do
  swapped=false
  for i=1,#ks-1 do
   if ks[i]>ks[i+1] then
    ks[i],ks[i+1]=ks[i+1],ks[i]
    vs[i],vs[i+1]=vs[i+1],vs[i]
    swapped=true
   end
  end
 end
end

-- the main rendering function
-- since almost everything is 
-- always on the screen at the
-- same time.
function draw_game()
 -- first, we adjust the pals so
 -- that it looks like the right
 -- time of day. (but if we get
 -- here and the palette is 
 -- already dark then just let it
 -- be.)
 if pal==original_pal then
  enable_sunshine(hour)
 end
	
	draw_map()
	
	-- make sure we draw the world
	-- objects in the right order.
	local draws={draw_player,draw_base,draw_penny}
	local ys={py*8+4,base_y*8+4,penny_y}
	sort(ys,draws)
	for dd in all(draws) do
	 dd()
	end
 
 -- (debugging garbage)
 --rectfill(sc.x-4,sc.y-4,sc.x+4,sc.y+4,7) 
 --local tc=looking_at()
 --sc=world_to_screen(tc.x,tc.y)
 --rectfill(sc.x-4,sc.y-4,sc.x+4,sc.y+4,10)
 
 -- now rain and stuff
 draw_weather()
 
 -- now turn off the palettes so
 -- that the menu and stuff 
 -- don't get affected by the 
 -- time of day.
 disable_dark()
 
 -- hud and debug stuff
 -- print("x "..x.." y "..y)
 if menu_mode then
  draw_menu(menu_items,menu_sel)
 elseif idle_time>1 then
  draw_item()
  draw_time()
  draw_meters()
 elseif (energy_level/max_energy)<0.25 then
  draw_meters()
 end
end

blank_screen=false 

function _draw()
 -- dirty hack: if you set 
 -- blank_screen to true then we
 -- won't bother drawing the 
 -- game. (cut-scenes use this
 -- to do a blackout.)
	if blank_screen then
	 cls(0)
	else
  draw_game()
 end
 
 -- the little box where people
 -- talk. (in 'cutscene stuff')
 draw_text()
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

-- these are all the live plants
plants={}

function update_plants()
 for p in all(plants) do
  local class=p.cls
  local age=p.age
  if age < #class.stages then
   -- update the age
   local new_age=age+class.rate
   if flr(new_age)~=flr(age) then
    mset(p.x+32,p.y,class.stages[flr(new_age)])
   end
   p.age=new_age
  end  
 end
end

function remove_plant(x,y)
 for p in all(plants) do
  if p.x==x and p.y==y then
   del(plants,p)
   return
  end
 end
end

function i_plant(item,tx,ty)
 if map_flag(tx,ty,1) then
  buzz()
  return
 end
 
 if energy_level<plant_cost then
  buzz()
  return
 end
 
 energy_level-=plant_cost
 local p=item.plant
 add(
  plants, 
  {age=1,x=tx,y=ty,cls=p})
 mset(tx+32,ty,p.stages[1])
end

function i_grab(item,tx,ty)
 local tgt=mget(tx+32,ty)
 if grabbed_item~=nil then
  -- drop
  if fget(tgt,0) or 
     tx < 0 or ty < 0 or 
     tx > 15 or ty > 15 then
   -- nopers
   buzz()
  else
   mset(tx,ty,64) -- bare dirt
   mset(tx+32,ty,grabbed_item)
   grabbed_item=nil
  end
 elseif fget(tgt,2) then
  if energy_level>grab_cost then
   energy_level-=grab_cost
   grabbed_item=tgt
   mset(tx+32,ty,0)
  else
   buzz()
  end
 end
end

function i_till(item,tx,ty)
 -- check *plowable*
 if not map_flag_all(tx,ty,3) then
  buzz()
  return
 end
 
 if energy_level<plow_cost then
  buzz()
  return
 end

 energy_level-=plow_cost
 animate(
  {{frame=33, duration=5}},
  function()
   if mget(tx+32,ty)~=0 then
    remove_plant(tx,ty)
    mset(tx+32,ty,0) -- destroy
   end
	  mset(tx,ty,66)    -- plowed  
	 end)
end

function init_items()
 item_sel=1
end

function get_items()
 return {
  -- pick axe hoe water
  {icon=142,name="grab",fn=i_grab},
  -- {icon=141,name="till",fn=i_till},
  -- {icon=143,name="water",fn=i_water},
  -- {icon=147,name="grass",fn=i_plant,plant=grass},
  -- {icon=163,name="mum",fn=i_plant,plant=mum},
 } 
end
-->8
-- water
function init_water()
 wet_map={}
 wet_map[64]=67
 wet_map[66]=68

 dry_map={}
 for k,v in pairs(wet_map) do
  dry_map[v]=k
 end
end

function i_water(item,tx,ty)
 if tank_level < 10 then
  buzz()
  return
 end
 
 if energy_level<water_cost then
  buzz()
  return
 end

 energy_level-=water_cost 
 animate(
  {{frame=35,duration=10}},
  function() 
   tank_level-=10
   local ground=mget(tx,ty)
   if wet_map[ground]~=nil then
    mset(tx,ty,wet_map[ground])
   end
  end)
end

-->8
-- weather
--
-- :todo: random weather on hour
-- and season. 
function init_weather()
 raining=false
 rain={}
 max_rain=2000
end

function update_weather()
 -- todo: check the time, see if
 --       weather changes.

 if raining and #rain<max_rain then
  for i=1,rnd(40) do
   add(rain, {
    x=flr(rnd(128)),
    y=flr(rnd(128))-3,
    life=flr(rnd(10))
   })
  end
 end
 
 for drop in all(rain) do
  drop.y+=3
  drop.x+=1
  drop.life-=1
  if drop.y>=128 
   or drop.life < 0 then
   del(rain,drop) 
  end
 end 
end

function draw_weather()
 for r in all(rain) do
  if r.life==0 then
   circ(r.x,r.y,1,12)
  else
   line(r.x,r.y-2,r.x+1,r.y,12)
  end
 end
end
-->8
-- fx
function init_fx()
 dark_levels={}
 for x=0,5 do
  local ramp={}
  for y=0,15 do
   ramp[y]=sget(x,y+40)
  end
  dark_levels[x]=ramp
 end
 original_pal=pal
 
 -- dark levels by hour.
 -- todo: should also factor in
 --       phase of moon?
 local sm={}
 for i=0,4   do sm[i]=3    end
 for i=5,8   do sm[i]=8-i  end
 for i=9,16  do sm[i]=0    end
 for i=17,19 do sm[i]=i-16 end
 for i=20,24 do sm[i]=3    end
 sunshine_map=sm
end

function enable_sunshine(t)
 enable_dark(sunshine_map[flr(t)])
end

function enable_dark(d)
 --assert(pal==original_pal)
 dark_level=dark_levels[d]
 pal(dark_level)
 pal=fx_pal
end

function disable_dark()
 pal=original_pal
 pal()
end

function fx_pal(s,t,p)
 local lvl=dark_level
 local opal=original_pal
 if type(s)=="table" then
  for k,v in all(s) do
   opal(k,lvl[v],p)
  end
 elseif s==nil and t==nil then
  opal(lvl,p)
 else
  opal(s,lvl[t],p)
 end
end

function fade_out(fn)
 fade_t=5
 fade_lvl=sunshine_map[flr(hour)]
 update_fn=update_fade
 fade_cb=fn
end

function update_fade()
 enable_dark(fade_lvl)
 fade_t-=1
 if fade_t<=0 then
  fade_lvl+=1
  if fade_lvl>5 then
   disable_dark()
   fade_cb()
  else
   fade_t=5
  end
 end
end

--[[
function dump_darkness()
 pal()
 for ilvl=1,#dark_levels do
  local lvl=dark_levels[ilvl]
  for ic=1,#lvl do
   local y=(ilvl-1)*4
   local x=(ic-1)*4
   rectfill(x,y,x+3,y+3,lvl[ic])
  end
 end
end
]]

-->8
-- cutscene stuff

-- portraits
py_think={top=192,bot=228}
py_shout={top=194,bot=230}
py_shock={top=194,bot=226}
py_frend={top=192,bot=224}
py_serio={top=194,bot=228}
py_talk={top=192,bot=226}
py_whelm={top=196,bot=224}

-- cutscenes.
cs_intro={
 {pre=function() 
   cls(0)
   penny_show(base_x*8+4,base_y*8+16,0)
   blank_screen=true
  end,
  "^penny?",
  "^p^e^n^n^y!",
  "...",
  "^where is that girl?"},
 {p=py_think,  
  "^o^k...\n^deep breath..."},
 {p=py_shout,
  "^r^x-228! ^activate!!!"},
 {pre=function()
   blank_screen=false
  end,
  p=py_shock,
  "^it... it works?",
  "^it works!"},
 {"^p^e^n^n^y? ^w^h^e^r^e ^a^r^e\n^y^o^u??"},
 {pre=function()
   penny_show(penny_x,penny_y,2)
  end,
  p=py_shout,
  "^c^o^m^i^n^g ^m^o^m!"},
 {pre=function()
   penny_show(penny_x,penny_y,0)
  end,
  p=py_frend,
  "^o^k. ^that's enough\nfor today.",
  "^you sit tight.",
  "^i'll be back soon to\nfinish up."},
 post=function()
  energy_level=max_energy/4
  penny_run(128,penny_y)
  update_fn=update_walk
  chapter=1
 end
}

cs_firstcharge={
 {pre=function()
   cls(0)
   penny_show(base_x*8+4,base_y*8+16,0)
   blank_screen=true
   
   -- ♪: set the chapter early
   --     so the base glows.
   chapter=2
  end,
  "...",
  "^hey... how'd you get\nover there?",
  "^oof...",
  "^there you go!"},
 {pre=function()
   blank_screen=false
  end,
  p=py_frend,
  "^huh...",
  "^i guess you really\n^d^o work!"},
 {p=py_shout,
  "^ha! ^i knew it!",
  "^i ^a^m ^t^h^e ^b^e^s^t!"},
 {p=py_talk,
  "^well, ^i've finished\nthis base.",
  "^if you stand there,\nyou'll recharge."},
 {p=py_frend,
  "^try not to run out\nof power, ok?"},
 {"^p^e^n^n^y!",
  "^t^h^a^t ^f^i^e^l^d ^c^l^e^a^r\n^y^e^t?"},
 {p=py_frend,
  "^oh, uh...",
  "^hey, help me clear\nthis field?",
  "^mom wants a big\nclear space..."},
 {p=py_whelm,
  "...but these rocks\nare so big."},
 {p=py_shock,
  "^help me move these,\n^o^k?"},
 post=function()
  penny_wander()
  update_fn=update_walk
  objective_fn=check_bigspace
 end
}

function check_bigspace()
 function check(x,y)
  for iy=0,6 do
   for ix=0,6 do
    if map_flag(x+ix,y+iy,0) then
     return false
    end
   end
  end
  return true
 end
 
 if (penny_x==nil) return
 if (grabbed_item) return
 
 for y=0,10 do
  for x=0,10 do
   if check(x,y) then
    do_script(cs_didclear)
   end
  end
 end
end

cs_didclear={
 {p=py_shock,
  "^hey!\n^you did it!"},
 {p=py_talk,
  "^wait a bit, i'll be back!"},
 post=function()
  penny_run(128,penny_y)
  update_fn=update_walk

  local start_hour=hour
  objective_fn=function()
   -- we'll use the objective
   -- hook to just wait an hour.
   if hour-start_hour>=1 then
    do_script(cs_up_tools)
   end
  end
 end
}

cs_up_tools={
 post=function()
  chapter=3
 end
}

--

cs_nobattery={
 {pre=function()
   old_penny_x=penny_x

   cls(0)
   penny_show(base_x*8+4,base_y*8+16,0)
   blank_screen=true
  end,
  "^robo?\n^can you hear me?"},
 {pre=function()
   blank_screen=false
  end,
  p=py_frend,
  "^oh, thank goodness."},
 {p=py_serio,
  "^robo, you need to be\nmore careful!",
  "^if you don't charge,\nyou'll get stuck!"},
 {p=py_frend,
  "^don't worry.",
  "^i'll always be there\nto help."},
 post=function()
  if old_penny_x==nil then
   penny_run(128,penny_y)
  end
  update_fn=update_walk
 end
}

--

function check_objective()
 if objective_fn then
  objective_fn()
 end
end

function do_script(script)
 local _coro=nil
 _coro=cocreate(function()
  local stage,s_line
  for stage in all(script) do
   if (stage.pre) stage.pre()
   local p=stage.p or {}
   for s_line in all(stage) do
    show_text(
     s_line,
     p.top, p.bot,
     function()
      assert(coresume(_coro))
     end)
    yield()
   end
  end
  if script.post then
   script:post()
  end
 end)
 assert(coresume(_coro))
end

function show_text(t,top,bot,next_fn)
 text=t
 text_time=0
 text_limit=#text+5
 text_sprite_top=top
 text_sprite_bot=bot
 text_next_fn=next_fn
 update_fn=update_text
end

function update_text()
 idle_time=0
 text_time=min(
  text_limit, 
  text_time+2)
 
 if btnp(🅾️) then
  text=nil
  text_next_fn()
 end
end

function draw_text()
 if (text==nil) return

 -- outline box
 draw_box(0,96,14,2)
 
 -- actual text
 local ss=sub(text,1,1+text_time)
 if sub(ss,-1,-1)=="^" then
  ss=sub(ss,1,-2)
 end
 draw_string(
  ss,
  28,114-11,7)
 if text_time==text_limit and
    time()%2>1 then
  print("🅾️",128-16,128-14,7)
 end

 -- portrait
 if text_sprite_top~=nil then
  spr(text_sprite_top,8,114-24,2,2)
  spr(text_sprite_bot,8,114-8,2,2)
 end
end

function init_penny()
 update_penny=nop
 
 penny_x=nil penny_y=0
 penny_t=0 penny_speed=0.09
 penny_frame=0
 penny_atime=0
 
 penny_d=0 -- -1,1,0,2
end

function penny_show(x,y,d)
 penny_x=x penny_y=y penny_d=d
 penny_frame=0
end

function penny_wander()
 function _next()
  local dst=flr(rnd()*16)
  local tx,ty=penny_x,penny_y
  if rnd()>=0.5 then
   tx=dst*8
  else
   ty=dst*8
  end
  tx=mid(8,tx,111)
  ty=mid(8,ty,111)
  penny_run(tx,ty,_idle)
 end

 function _sleep()
  local sd=day 
  penny_x=nil 
  update_penny=function()
   -- wait for morning.
   if day>sd and hour>=8 then
    penny_x=128
    penny_y=flr(rnd()*103)+8
    local tx=flr(rnd()*103)+8
    penny_run(tx,penny_y,_idle)
   end
  end
 end
 
 function _idle()
  local t=(rnd()*30)+20
  update_penny=function()
   if hour>=18 then
    -- penny, it's late! run 
    -- home to mom!
    penny_run(128,penny_y,_sleep)
   else
    t-=1
    if t<=0 then
     _next()
    else
     check_objective()
    end 
   end
  end
 end
 
 _next()
end

function penny_stop_wander()
 update_penny=nop
 penny_frame=0
end

function penny_run(tx,ty,fn)
 local dx=tx-penny_x
 local dy=ty-penny_y
 if abs(dx)>abs(dy) then
  if dx>0 then 
   penny_d=1 
  else
   penny_d=-1
  end
 else
  if dy>0 then
   penny_d=2
  else
   penny_d=0
  end
 end
 
 penny_t=0
 update_penny=function()
  penny_t+=penny_speed
  
  penny_atime+=penny_speed
  while penny_atime>=1 do
   penny_atime-=1
  end

  local dist=(sin(penny_t)+1)*3
  if penny_d==0 then
   penny_y-=dist
   if (penny_y<ty) penny_y=ty
  elseif penny_d==2 then
   penny_y+=dist
   if (penny_y>ty) penny_y=ty
  elseif penny_d==-1 then
   penny_x-=dist
   if (penny_x<tx) penny_x=tx
  else
   penny_x+=dist
   if (penny_x>tx) penny_x=tx
	 end
  
  -- 2 frames, 2 wide
  penny_frame=flr(penny_atime*2)*2
  
  if penny_x==tx and
     penny_y==ty then
   penny_frame=0
   update_penny=nop
   if fn then 
    fn() 
   else
    penny_x=nil
   end
  end
 end
end

function nop() end

function draw_penny()
 if penny_x~=nil then
  local base,w,f,m=74,1,false,16
  if penny_d==1 then
   base=76 w=2 m=1
  elseif penny_d==-1 then
   base=76 w=2 m=1 f=true
  elseif penny_d==2 then
   base=75
  end
  spr(
   base+(penny_frame*m),
   penny_x-4,
   penny_y-16,
   w,2,
   f)
 end
end
-->8
-- big font code
--
-- call load_font() then when
-- you want call draw_string()
-- to draw what you want. 
-- the font has upper case a-z,
-- lower case a-z, digits 0-9,
-- and some punctuation.
font_enc=[[414869999f994248caae999e4348699889964448e999999e4548f88e888f4648f88e888847486998b9964848999f99994918ff4a48111111964b48999e99994c488888888f4d58dd6b18c6314e489ddbb9994f48699999965048e99e8888515864a5295a4d5248e99e99995348698611965438e9249255489999999656588c6315294457588c6318d6aa58588a9442295159588c62a210845a48f122448f615564a52680624788e999606345698960644711799960654569f8706647254e444067456971e0684788e999906917be6a47101119606b478899e9906c27aaa46d55556b18806e45ad99906f456999607045699e8071456997107245ad988073457861e074374ba490754599996076558c54a20077558c6b550078558a88a88079459971e07a45f168f03048699bd996313859249732486911248f3348691211963448aaaf22223548f88e11963648698e99963748f11248883848699699963948699711112118fd3f5874622210042e11803a16902c2358272858002d44f000]]

function load_font()
 local enc,bytes=font_enc,{}
 for i=1,#enc,2 do
  add(bytes,tonum("0x"..sub(enc,i,i+1)))
 end
 
 local font,bi={},1
 while bi<#bytes do
  local c=bytes[bi] bi+=1
  
  local bmap={bytes[bi]}
  local b=bmap[1]
  local w,h=(b&0xf0)>>4,b&0x0f
  local bytec=ceil(w*h/8)
  for j=1,bytec do
   add(bmap,bytes[bi+j])
  end
  bi+=bytec+1
  
  font[c]={w=w,h=h,bmap=bmap}
 end
 
 _jd_font=font
end

-- render a single glyph at x,y
-- in the current color.
function draw_font_glyph(glyph,x,y)
 local bi,bits=2,0
 local bmap=glyph.bmap
 local byte=bmap[bi]
 for iy=8-glyph.h,7 do
  for ix=0,glyph.w-1 do
   if byte&0x80>0 then
    pset(x+ix,y+iy)    
   end
   -- advance bits
   byte<<=1 bits+=1
   if bits==8 then
    -- advance bytes
    bi+=1 byte=bmap[bi] bits=0
   end
  end
 end
end

-- render a string in the font
-- with the upper-left at x,y.
-- specify upper-case letters 
-- by prefixing them with a ^.
--
-- (e.g., "^e" renders an 
-- upper-case e.)
--
-- if c is provided, the current
-- color will be set to that 
-- color first.
function draw_string(str,x,y,c)
 if c~=nil then color(c) end
 local lx,ly=x,y
 local i,font=1,_jd_font
 while i<=#str do
  local c=sub(str,i,i) i+=1
  if c==" " then
   lx+=4
  elseif c=="\n" then
   lx=x ly+=10
  else
   if c=="^" then
    c=sub(str,i,i) i+=1
    c=ord(c)-32
   else
    c=ord(c)
   end
   
   local glyph=font[c]
   assert(glyph~=nil, "char "..c.." not in font")
   draw_font_glyph(glyph,lx,ly)
   lx+=glyph.w+1
  end
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
c00cc00c00cccccccccccc0000cccccccccccc00ccc0ccccccccccccccc0cccccccc000000cccccccccccc0000cccc0000cccc00000000000000000000000000
0ee00ee0070c00000000c070070c00000000c07000070c00000ccccc00070c0000000770070c00000000c070070c00000000c070000000000000000000000000
0e0ee0e0c07007777770070cc07007777770070c070700e007700ccc070700e00077070cc07007777770070cc07007777770070c000000000000000000000000
0e0e5e00cc007000000700cccc007000000700ccc0700ee0000770ccc0700ee007700770cc070000000070cccc070000000070cc000000000000000000000000
00e5e0ccccc0000000000cccc00000700700000ccc00eee00000770ccc00ee0077000000ccc0700000070cccc00070000007000c000000000000000000000000
c000000cccc000e00e000ccc0e7007e00e7007e0cc0ee00e0000070ccc0ee0077000070cccc0070000700ccc0770070000700770000000000000000000000000
0eee0ee0c00000e00e00000c0e70eee00eee07e0cc0e0770e000070ccc0e00770000070cc00000777700000c0770007777000770000000000000000000000000
000000000e700000000007e0c000ee0000ee000ccc0070000000070ccc0070000000070c07700070070007700770007007000770000000000000000000000000
000000000e707000000707e0cc000000000000cccc0e00770000000ccc0e07707000000c07707000000707700ee0700000070ee0000000000000000000000000
000000000ee0777777770ee0ccc0777777770ccccc0ee0077000000ccc0ee00e7700000c077070eeee070770c00070eeee07000c000000000000000000000000
000000000ee0077777700ee0ccc0777777770ccccc0eee007700770ccc0eeeee7777770c0ee0e0eeee0e0ee0ccc0e0eeee0e0ccc000000000000000000000000
00000000c00000777700000cccc0777777770ccccc0eeee007700000cc0eeeee7777770c0000ee0000ee0000ccc0ee0000ee0ccc000000000000000000000000
00000000cc00e700007e00ccccc0077777700cccccc0000e00770770ccc0000e777770ccc0000eeeeee0000cccc00eeeeee00ccc000000000000000000000000
00000000ccc0ee7007ee0cccccc0000000000ccccc0000000000070ccc00000000000ccccc000000000000ccccc0000000000ccc000000000000000000000000
00000000ccc00ee00ee00cccccc0eee00eee0ccccc0e0c0e0e0e0770cc0e0c0e0e0e0cccccc0e00ee00e0cccccc0eee00eee0ccc000000000000000000000000
00000000ccc0000000000cccccc0000000000ccccc000c0000000000cc000c0000000cccccc0000000000cccccc0000000000ccc000000000000000000000000
44444444056666005445444555555555155155510000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
45444444665556604544545451555555515515150000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
444445446665666645454454555551555151551500000000000000000000000000000000000000000ff0ff000ff0ff0000000000000000000000000000000000
44444444665566665445444555555555155155510000000000000000000000000000000000000000fff0fff0fef0fef0000fe000000000000000000000000000
44444444556655654544545455555555515515150000000000000000000000000000000000000000fff0fff0fef0fef0000fe000000000000000eeeee0000000
44445444666565654545445455551555515155150000000000000000000000000000000000000000fff0fff0fef0fef0000ffe00000000000000fffffe000000
44544444065566505445444555155555155155510000000000000000000000000000000000000000fff0fff0fef0fef00000ff000000000000000000fffff7f0
444444440055550045445454555555555155151500000000000000000000000000000000000000000ff0ff000ff0ff0000000f000000000000000000000f7dfe
000000000000000000000000444444440000000000000000000000000000000000000000000000000fffff000fffff000000ff7f00000000077ffffff00fffff
11100011110000000000000044444444000000000000000000000000000000000000000000000000fffffff0ff7f7ff00000f7dfe0000000077ffffffffffff0
22110025211000000000000044444444000000000000000000000000000000000000000000000000fffffff0f7dfd7f00000fffff000000000fffffffffff000
33311033331100000000000044444444000000000000000000000000000000000000000000000000fffffff0fffefff000ffffff000000000ffffffffffff000
4221102d44221000000000004444444400000000000000000000000000000000000000000000000000fff00000fff00077fffff000000000fff000000ffffff0
551110555511000000000000444554440000000000000000000000000000000000000000000000000fffff000fffff0077fffff0000000000000000000000000
66d5106666dd51000000000044455444000000000000000000000000000000000000000000000000fff7fff0ffefeff0fffefff0000000000000000000000000
776d1077776dd5500000000044444444000000000000000000000000000000000000000000000000ff777ff0ffefeff0ffffefff000000000000000000000000
88221018888221000000000000000000000000000000000000000000000000000000000000000000f00000f0f00000f000000000000000000000000000000000
9422104c999421000000000000000000000000000000000000000000000000000000000000000000f0fff0f0ff000ff000000000000000000000000000000000
a9421047aa9942100000000000000111000000000000000000000000000000000000000000000000f0fef0f0ff000ff000000000000000000000000000000000
bb3310bbbbb3310000000000000001a100000000000000000000000000000000000000000000000007dfd7000f070f0000000000000000000000000000000000
ccd510ccccdd51100000000000001161000000000000000000000000000000000000000000000000ff7f7ff00f777f0000000000000000000000000000000000
d55110dddd5110000000000000001aa1000000000000000000000000000000000000000000000000fdfffdf00ff7ff0000000000000000000000000000000000
ee82101eee8822100000000000111661000000000000000000000000000000000000000000000000fdfffdf00fffff0000000000000000000000000000000000
f94210f7fff9421000000000001aaaa1000000000000000000000000000000000000000000000000fdfffdf0fffffff000000000000000000000000000000000
00000000000000006666666600116661000000000000000000000000000000000000000000000000fffffff0fefffef000000000000000000000000000000000
0000000000000000666666660001aaa1000000000000000000000000000000000000000000000000fffffff0fefffef000000000000000000000000000000000
000000000000000066566566011166610000000000000000000000000000000000000000000000000ff7ff00fefffef000000000000000000000000000000000
00000000000000006656656601aaaaa10000000000000000000000000000000000000000000000000f777f000f7f7f0000000000000000000000000000000000
000000000000000066566566011666610000000000000000000000000000000000000000000000000f070f00f7dfd7f000000000000000000000000000000000
000000000000000066566566001aaaa1000000000000000000000000000000000000000000000000ff000ff0f0fef0f000000000000000000000000000000000
00000000000000006656656611166661000000000000000000000000000000000000000000000000ff000ff0f0fff0f000000000000000000000000000000000
0000000000000000666666661aaaaaa1000000000000000000000000000000000000000000000000f00000f0f00000f000000000000000000000000000000000
cccccccccccccccccc53350000000500000000000000000000555500005555000055550000555500005555000055550000000000665555000006666000076000
cccccccccccccccccc53350000000050000005000990909005777750057777500577755005777550057755500555555000000000566777500067777607666660
cccc555555555555cc53350000000505000033500099999057777775577777555777755557775555577555555555555500000000056677656677666600000000
ccc5533333333333cc5335000000500000099335099aa9005777777557777775577775555777555557755555555555550000000057565665777655550c0c0c00
cc55333333333333cc5335000005000000998053009aa99057777775577777755777755557775555577555555555555500000000577556657776000000000000
cc53335555555555cc53350006650000099800300999990057777775577777555777755557775555577555555555555500000000544666456677666600c0c0c0
cc53350000000000cc53350067650000998000000909099005777750057777500577755005777550057755500555555000000000445464540067777600000000
cc53350000000000cc5335007650000098000000000000000055550000555500005555000055550000555500005555000000000045444444000666600c0c0c00
000000000000000000000000b0000b00000000000000000000000000000000000000000000000000000000000000000000000000665555000000000000000000
0000000000000000000000003b00b3bb000000000000000000000000000000000000000000000000000000000000000000000000566777500000000000000000
00000000000000000000b0b00b0b3b30000000000000000000000000000000000000000000000000000000000000000000000000056677650000000000000000
0000000000000000000b0b0003b30b30000000000000000000000000000000000000000000000000000000000000000000000000575656650000000000000000
0000000000000b0000b30b00b0b3b300000000000000000000000000000000000000000000000000000000000000000000000000577556650000000000000000
000000000b000b00b0b30b00b0b3b30b000000000000000000000000000000000000000000000000000000000000000000000000577666650000000000000000
0b00b0000b300b300b300bb00bb3b3b0000000000000000000000000000000000000000000000000000000000000000000000000056666500000000000000000
00b0b0bb03b0b3b00b30b3b00bb3b3b0000000000000000000000000000000000000000000000000000000000000000000000000005555000000000000000000
000000000000000000000000ddd00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000ddd00000dad0ddd0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000ddd00000ddd0dad0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000b3000000b300ddd0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000003b0000003dd0dd00ddd0300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
030000000300000003dd0dd00dad03b0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000030b3000030b3000dddb300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00300300003003000030030000300300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000ff00ff0000000000ff0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000fef00fef00000000fef0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000feeeffeeef000000feeef000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000ffff000feeeeffeeeef0000feeeef000ffff000fff00000000000000000000000000000000000000000000000000000000000000000000000000000000000
00ffffff00feeeeffeeeef0000feeeef00ffffff00fffff000000000000000000000000000000000000000000000000000000000000000000000000000000000
0fffffff00feeeeffeeeef0000feeeef0fffffff00fffff000000000000000000000000000000000000000000000000000000000000000000000000000000000
0fffffff00feeeeffeeeef0000feeeef0fffffff00fffff000000000000000000000000000000000000000000000000000000000000000000000000000000000
ffffffef0feeeeeffeeeeef00feeeeefffffffef0fffffff00000000000000000000000000000000000000000000000000000000000000000000000000000000
fffffeef0feeeeeffeeeeef00feeeeeffffffeef0fefffff00000000000000000000000000000000000000000000000000000000000000000000000000000000
fffffeef0feeeef00feeeeef0feeeef0fffffeef0feeffff00000000000000000000000000000000000000000000000000000000000000000000000000000000
ffffeeef0feeeef00feeeeef0feeeef0ffffeeef0feeffff00000000000000000000000000000000000000000000000000000000000000000000000000000000
ffffeeef0feeef0000feeeef0feeef00ffffeeef0feeefff00000000000000000000000000000000000000000000000000000000000000000000000000000000
ffffeeef0feeef0000feeeef0feeef00ffffeeef0feeefff00000000000000000000000000000000000000000000000000000000000000000000000000000000
ff0feeef0feeef0000feeeef0feeef00ff0feeef0feeeff000000000000000000000000000000000000000000000000000000000000000000000000000000000
f00feeef0feef000000feeef0feef000f00feeef0feef00000000000000000000000000000000000000000000000000000000000000000000000000000000000
000feeef0feef000000feeef0feef000000feeef0feef00000000000000000000000000000000000000000000000000000000000000000000000000000000000
000feffffffef000000feffffffef000000feffffffef000000feffffffef0000000000000000000000000000000000000000000000000000000000000000000
000ffffffffff000000ffffffffff000000ffffffffff000000ffffffffff0000000000000000000000000000000000000000000000000000000000000000000
00ffffffffffff0000ffffffffffff0000ffffffffffff0000ffffffffffff000000000000000000000000000000000000000000000000000000000000000000
00fffeffffefff0000ffffffffffff0000ffffffffffff0000ffffffffffff000000000000000000000000000000000000000000000000000000000000000000
0ffeeffffffeeff00fffeeffffeefff00ffeeffffffeeff00ffeeffffffeeff00000000000000000000000000000000000000000000000000000000000000000
0feffffffffffef00ffeffffffffeff00ffffeffffeffff00ffffeffffeffff00000000000000000000000000000000000000000000000000000000000000000
0fff77ffff77fff00fff77ffff77fff00ffffffffffffff00fff77ffff77fff00000000000000000000000000000000000000000000000000000000000000000
fff7ddffffdd7ffffff7ddffffdd7ffffffeffffffffeffffff7ddffffdd7fff0000000000000000000000000000000000000000000000000000000000000000
fff7ddffffdd7ffffff7ddffffdd7fffffffeeffffeefffffff7ddffffdd7fff0000000000000000000000000000000000000000000000000000000000000000
fffffffffffffffffffffffeeffffffffffffffeeffffffffffffffeefffffff0000000000000000000000000000000000000000000000000000000000000000
ffffffeeeeffffffffffffeeeeffffffffffffeeeeffffffffffffeeeeffffff0000000000000000000000000000000000000000000000000000000000000000
fffffffeefffffffffffffffffffffffffffffffffffffffffffffffffffffff0000000000000000000000000000000000000000000000000000000000000000
fffffeffffffffffffffffe77effffffffffffffffffffffffffffeeeeffffff0000000000000000000000000000000000000000000000000000000000000000
ffffffeeffffffffffffffeeeeffffffffffffeeeeffffffffffffeeeeffffff0000000000000000000000000000000000000000000000000000000000000000
00ffffffffffff0000fffffeefffff0000ffffffffffff0000fffffeefffff000000000000000000000000000000000000000000000000000000000000000000
__gff__
0800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008071828380000000000000000000000000000030000000000000000000000000000000300000000000000000000000000000003000000000000000000000000
000000000000000000000000000000000a0a0a0a0000000000000000000000000a0a0a0a0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
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
__sfx__
000500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
