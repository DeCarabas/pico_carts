pico-8 cartridge // http://www.pico-8.com
version 36
__lua__
// CB
// (c) John Doty 2022

-- Items
-- - Inertial Dampener (jump higher)
-- - Inertial Amplifier (push blocks)
-- - Hard-light projector (double-jump)
-- - Radio (talk over long distances)
-- - Crypto Module (unlock doors)
-- - Batman Grapple (vertical and horizontal movement)

-- NOTE: Taking some stuff from eevee's aborted blog series


vec2={}
vec2.__index=vec2
function vec2:__add(o)
  return vec(self.x+o.x,self.y+o.y)
end
function vec2:__sub(o)
  return vec(self.x-o.x,self.y-o.y)
end
function vec2:__div(o)
  return vec(self.x/o, self.y/o)
end
function vec2:__mul(o)
  return vec(self.x*o, self.y*o)
end
function vec2:__tostring()
  return "("..self.x..","..self.y..")"
end
function vec2:length()
  return sqrt(self.x*self.x+self.y*self.y)
end
function vec(x,y)
  -- todo: if i don't end up using unpack here then
  -- i can just remove that x,y thingy in there
  return setmetatable({x,y,x=x,y=y},vec2)
end

local clock=0

-- TODO: Collapse to save tokens obviously
local frames={1,2,3,2}
local player_velocity=vec(0,0)
local player_position=vec(64,0)
local player_frame=1

-- Physics constants, ala 2dengine.com
-- TODO: obviously collapse for tokens
local c_jump_height=32 -- in pixels
local c_time_to_apex=16 -- in frames, not seconds!
local c_damping=1
local c_gravity=2 * c_jump_height / (c_time_to_apex * c_time_to_apex)
local c_jump_velocity=sqrt(2*c_jump_height*c_gravity)

local dbg_max_mag=0

-- todo: i feel like this should all be ... compressable.

-- returns the new center y position if we bonk vertically
function vertical_collide(old_position,new_position,velocity)
  local x,dx=old_position.x,velocity.x/velocity.y

  local sign=velocity.y>0 and 1 or -1
  local delta=sign*8 -- hh

  for ty=(old_position.y+delta)\8,(new_position.y+delta)\8,sign do
    for tx=(x-3)\8,(x+3)\8 do
      local tile=mget(tx,ty)
      if fget(tile,0) then
        -- this returns +0 if sign is positive (the top edge)
        -- this returns +8 if sign is negative (the bottom edge)
        return ty*8 + (4 - 4*sign) - delta
      end
    end
    -- the outer loop moves along the y axis, this moves us the
    -- corresponding amount in the x axis
    x += dx
  end
end


function find_wall_right(old_position,new_position,velocity)
  local y,dy=old_position.y,velocity.y/velocity.x

  for tx=(old_position.x+4)\8,(new_position.x+4)\8 do
    for ty=(y-7)\8,(y+7)\8 do
      local tile=mget(tx,ty)
      if fget(tile,0) then
        return tx*8
      end
    end
    y += dy
  end
end

function find_wall_left(old_position,new_position,velocity)
  local y,dy=old_position.y,velocity.y/velocity.x

  for tx=(old_position.x-4)\8,(new_position.x-4)\8,-1 do
    for ty=(y-7)\8,(y+7)\8 do
      local tile=mget(tx,ty)
      if fget(tile,0) then
        return tx*8+7
      end
    end
    y += dy
  end
end


function _update60()
  -- ===========================
  -- A global clock to drive
  -- animations and stuff
  -- ===========================
  -- (From eevee)
  clock += 1
  clock %= 27720

  -- ===========================
  -- Player input
  -- ===========================
  -- From 2dplatformer.com
  -- NOTE: These equations
  -- probably will need
  -- simplified later but for
  -- now they can be all fancy
  -- and stuff.
  local walking
  if btn(⬅️) then
    if player_grounded then
      walking = true
      facing = "left"
    end
    player_velocity.x -= 1
  end
  if btn(➡️) then
    if player_grounded then
      walking = true
      facing = "right"
    end
    player_velocity.x += 1
  end

  if btn(🅾️) and player_grounded then
    player_velocity.y = -c_jump_velocity
    player_grounded = false
  end
  player_velocity.y += c_gravity
  player_velocity.x /= 1 + c_damping

  local velocity_magnitude = player_velocity:length()
  dbg_max_mag = max(dbg_max_mag, velocity_magnitude) --dbg

  -- ====================================================
  -- collision detection
  -- ====================================================
  local new_position = player_position + player_velocity
  if player_velocity.y~=0 then
    local bonk_y = vertical_collide(player_position,new_position,player_velocity)
    player_grounded = bonk_y and bonk_y >= player_position.y
    if bonk_y then
      new_position.y = bonk_y
      player_velocity.y = 0
    end
  end

  -- if player_velocity.y>0 then
  --   local ground_y = vertical_collide(player_position,new_position,player_velocity)
  --   if ground_y then
  --     new_position.y = ground_y - 8

  --     player_grounded = true
  --   else
  --     player_grounded = false
  --   end
  -- elseif player_velocity.y<0 then
  --   local ceiling_y = vertical_collide(player_position,new_position,player_velocity)
  --   if ceiling_y then
  --     new_position.y = ceiling_y + 8
  --     player_velocity.y = 0
  --   end
  -- end

  if player_velocity.x>0 then
    local wall_x = find_wall_right(player_position,new_position,player_velocity)
    if wall_x then
      new_position.x = wall_x - 5
      player_velocity.x = 0
      player_wall_right = true
    else
      player_wall_right = false
    end
  elseif player_velocity.x<0 then
    local wall_x = find_wall_left(player_position,new_position,player_velocity)
    if wall_x then
      new_position.x = wall_x + 5
      player_velocity.x = 0
      player_wall_right = true
    else
      player_wall_right = false
    end
  end

  player_position = new_position

  if walking then
    player_frame=(player_frame+0.2)%2
  end
end

function _draw()
  cls()
  map(0,0)

  -- TODO: Fix this dang stuff here.
  idx=frames[flr(player_frame+1)]
  spr(
    idx,
    player_position.x-4,
    player_position.y-8,
    1, 2,
    facing=="left"
  )
  -- pset(player_position.x,player_position.y,12)
  -- print(dbg_max_mag.." p="..tostr(player_position).." v="..tostr(player_velocity))
end

__gfx__
000000000000000000ee00ee00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000e000e00edd0edd00e000e0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
007007000ede0edeedd0edd00ede0ede000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00077000edddeddded00ed00edddeddd000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00077000ed00ed00edd0ed00ed00ed00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00700700edd0ed00eedeeee0edd0ed00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000eedeeee00eeee7eeeedeeee0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000eeee7ee0eeee0ee0eeee7ee000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000eeee0ee00eeeee70eeee0ee000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000eeeee700eeeee000eeeee7000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000eeeee0000eed0000eeeee0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000eed0000eed000000eed00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000eeeee0007eeed0007eeee00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000ddede5007dede0007dedee0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000150ee00000ed0000de05500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000005550eee000eee000eee0055000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
22222222000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
2edeede2000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
2deedee2000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
2eedeed2000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
2edeede2000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
2deedee2000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
2eedeed2000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
22222222000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__gff__
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__map__
4000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
4000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
4000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
4000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
4000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
4000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
4000000040404000000000000000004000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
4000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
4000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
4000000000000000004040400000004000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
4000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
4000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
4040404040404040404040404040404000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
