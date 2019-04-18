pico-8 cartridge // http://www.pico-8.com
version 16
__lua__
leaves_enabled=true

function reset()
 local base={x=64,y=96,w=0.5}
 segs={base}
 tips={{
  x=base.x,y=base.y,w=0.5,
  p=base,
  vec={x=0,y=-1},
  leaves={},
 }}
 leaves={}
 min_y=base.y
 max_y=base.y
 max_x=base.x
 min_x=base.x
end

function _init()
 reset()
end

function bud(p)
 return {
  x=p.x,y=p.y,w=0.5,p=p,
  vec={
   x=p.vec.x+rnd(0.8)-0.4,
   y=p.vec.y,
  },
  leaves={},
 }
end

function grow(tip)
 -- sprout out a new branch,
 -- yeah?
 if rnd(100)>97 then
  return {tip,bud(tip)}
 -- new segment, move in a new
 -- direction.
 elseif rnd(100)>90 then
  add(segs,tip)
  return {bud(tip)}
 else
  tip.x+=tip.vec.x
  tip.y+=tip.vec.y
  min_y=min(min_y,tip.y)
  max_y=max(max_y,tip.y)
  min_x=min(min_x,tip.x)
  max_x=max(max_x,tip.x)
  return {tip}
 end 
end

function _update()
 if btnp(4) then
  reset()
 end
 if btnp(5) then 
  leaves_enabled=not leaves_enabled
 end
 
 -- ★so much alloc★
 local new_tips={}
 for tip in all(tips) do
  if tip.y<=10 then
   add(segs,tip)
  else   
   local nts=grow(tip)
   for nt in all(nts) do
    add(new_tips, nt)
   end
  end
 end
 tips=new_tips
    
 -- everybody grow a little.
 local grow_ok=#tips>0
 if grow_ok and rnd(100)>70 then
  for seg in all(segs) do
   seg.w+=0.2
  end    
 end 
 
 -- leaves?
 if grow_ok then
  local width=max_x-min_x
  local height=max_y-min_y
  local canopy=height/3
  local center=(max_x+min_x)/2

  -- prune old leaves
  for seg in all(segs) do
   if seg.y>canopy then
    seg.leaves={}
   end
  end

  -- grow leaves on the tips
  for i=1,#tips do
   local t=tips[i]
   local x=rnd(10)-5
   local y=rnd(10)-5
   local r=rnd(10)+5
   add(t.leaves,{x=x,y=y,r=r})
  end
 end
end

function draw_trunk(seg)
 local seg0=seg.p
 pts={
  {x=seg0.x-seg0.w,y=seg0.y},
  {x=seg0.x+seg0.w,y=seg0.y},
  {x=seg.x-seg.w,y=seg.y},
  {x=seg.x+seg.w,y=seg.y},
 }
 color(4)
 trifill({pts[1],pts[2],pts[3]})
 trifill({pts[2],pts[3],pts[4]})
 for i=1,max(2,seg.w) do
  line(pts[1].x+i-1,pts[1].y,
   pts[3].x+i-1,pts[3].y, 5)
 end
end

function draw_seg(seg)
 draw_trunk(seg) 
 if leaves_enabled then
  for leaf in all(seg.leaves) do
   circfill(seg.x+leaf.x,
    seg.y+leaf.y,leaf.r,5)
   circfill(seg.x+leaf.x+2,
    seg.y+leaf.y-2,leaf.r,3)   
  end
 end
end

function _draw()
 cls()

 -- tri_test()
 color(4)
 for i=2,#segs do 
  draw_seg(segs[i])
 end

 for tip in all(tips) do
  draw_seg(tip)
 end
 
 -- color(7)
 -- print("t "..#tips.."l "..#leaves)
end
-->8
-- ⧗triangles⧗
function isort(t, cmp)
 for i=2,#t do
  local j=i
  while(j>1 and cmp(t[j-1],t[j])>0) do
   local tx=t[j-1]
   t[j-1]=t[j]
   t[j]=tx
   j-=1
  end
 end
end

function trifill_top(
 y0,y1,x0,x1,x2)
 local dy=y1-y0
 local dx1=(x1-x0)/dy
 local dx2=(x2-x0)/dy
 
 local lx1=x0
 local lx2=x0
 for y=y0,y1 do
  line(lx1,y,lx2,y)
  lx1+=dx1
  lx2+=dx2
 end
end

function trifill_bottom(
 y0,y1,x1,x2,x3)
 local dy=y1-y0
 local dx1=(x3-x1)/dy
 local dx2=(x3-x2)/dy
 
 local lx1=x1
 local lx2=x2
 for y=y0,y1 do
  line(lx1,y,lx2,y)
  lx1+=dx1
  lx2+=dx2
 end
end

function trifill(pts)
 isort(pts, function(pa,pb) 
  return pa.y-pb.y
 end)

 if pts[1].y==pts[2].y then
  -- only the bottom of a tri
  trifill_bottom(
   pts[1].y,pts[3].y,
   pts[1].x,pts[2].x,pts[3].x)
 elseif pts[2].y==pts[3].y then
  -- only the top part
  trifill_top(
   pts[1].y,pts[3].y,
   pts[1].x,pts[2].x,pts[3].x)
 else
  -- both parts; find the mid-x
  local dy=pts[3].y-pts[1].y
  local my=pts[2].y-pts[1].y
  local dx=pts[3].x-pts[1].x
  local mx=pts[1].x+dx*(my/dy)
  trifill_top(
   pts[1].y,pts[2].y,
   pts[1].x,pts[2].x,mx)
  trifill_bottom(
   pts[2].y,pts[3].y,
   pts[2].x,mx,pts[3].x)
 end
end

function tri_test()
 tri_test_pts={
   {x=32,y=32},
   {x=96,y=32},
   {x=64,y=96},
 }
 
 trifill(tri_test_pts)
end
