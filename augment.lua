require 'datasources.datasource'
require 'paths'
require 'image'
require 'math'

local function round(x)
   return math.floor(x+0.5)
end

local AugmentDatasource, parent = torch.class('AugmentDatasource', 'ClassDatasource')

function AugmentDatasource:__init(datasource, params)
   parent.__init(self)
   self.datasource = datasource
   self.nChannels, self.nClasses = datasource.nChannels, datasource.nClasses
   if params.cropSize then
      assert(#(params.cropSize) == 2)
      self.h, self.w = params.cropSize[1], params.cropSize[2]
   else
      self.h, self.w = datasource.h, datasource.w
   end

   if self.datasource.tensortype == 'torch.CudaTensor' then
      print("Warning: AugmentDatasource used with a cuda datasource. Might break")
   end
  
   if params.resize ~= nil then
	UsingResize = true
   else 
	UsingResize = false
   end

   -- resize can't be used together with crop
   self.params = {
      resize = params.resize or {self.h, self.w},
      mean = params.rgb_mean or {0, 0, 0}, -- RGB
      rgb2bgr = params.rgb2bgr or false,
      flip = params.flip or 0, --1 for vflip, 2 for hflip, 3 for both
      crop = params.crop or {self.h, self.w},
      scaleup = params.scaleup or 1,
      rotate = params.rotate or 0,
      cropMinimumMotion = params.cropMinimumMotion or nil,
      cropMinimumMotionNTries = params.cropMinimumMotionNTries or 25,
   }
end

local function flatten3d(x)
   -- if x is a video, flatten it
   if x:dim() == 4 then
      return x:view(x:size(1)*x:size(2), x:size(3), x:size(4))
   else
      assert(x:dim() == 3)
      return x
   end
end

local function dimxy(x)
   assert((x:dim() == 3) or (x:dim() == 4))
   if x:dim() == 4 then
      return 3, 4
   else
      return 2, 3
   end
end

local flip_out1, flip_out2 = torch.Tensor(), torch.Tensor()
local function flip(patch, mode)
   local out = patch
   if (mode == 1) or (mode == 3) then
      if torch.bernoulli(0.5) == 1 then
	 flip_out1:typeAs(out):resizeAs(out)
	 image.vflip(flatten3d(flip_out1), flatten3d(out))
	 out = flip_out1
      end
   end
   if (mode == 2) or (mode == 3) then
      if torch.bernoulli(0.5) == 1 then
	 flip_out2:typeAs(out):resizeAs(out)
	 image.hflip(flatten3d(flip_out2), flatten3d(out))
	 out = flip_out2
      end
   end
   return out
end

local function crop(patch, hTarget, wTarget, minMotion, minMotionNTries)
   local dimy, dimx = dimxy(patch)
   local h, w = patch:size(dimy), patch:size(dimx)
   assert((h >= hTarget) and (w >= wTarget))
   if (h == hTarget) and (w == wTarget) then
      return patch
   else
      if minMotion then
	 assert(patch:dim() == 4)
	 local x, y
	 for i = 1, minMotionNTries do
	    y = torch.random(1, h-hTarget+1)
	    x = torch.random(1, w-wTarget+1)
	    local cropped = patch:narrow(dimy, y, hTarget):narrow(dimx, x, wTarget)
	    if (cropped[-1] - cropped[-2]):norm() > math.sqrt(minMotion * cropped[-1]:nElement()) then
	       break
	    end
	 end
	 return patch:narrow(dimy, y, hTarget):narrow(dimx, x, wTarget)
      else
	 local y = torch.random(1, h-hTarget+1)
	 local x = torch.random(1, w-wTarget+1)
	 return patch:narrow(dimy, y, hTarget):narrow(dimx, x, wTarget)
      end
   end
end

local resize_out = torch.Tensor()
local function resize(patch, size_, mode)
   mode = mode or 'bilinear'
   local new_x = size_[2] -- w
   local new_y = size_[1] -- h
   local dimy, dimx = dimxy(patch)
   local h, w = patch:size(dimy), patch:size(dimx)
   if (new_y == h) and (new_x == w) then
      return patch
   else
      if patch:dim() == 3 then
	 resize_out:typeAs(patch):resize(patch:size(1), new_y, new_x)
      else
	 resize_out:typeAs(patch):resize(patch:size(1), patch:size(2), new_y, new_x)
      end
      return image.scale(flatten3d(resize_out), flatten3d(patch), mode)
   end
end

local scaleup_out = torch.Tensor()
local function scaleup(patch, maxscale, mode)
   mode = mode or 'bilinear'
   local dimy, dimx = dimxy(patch)
   assert(maxscale >= 1)
   local h, w = patch:size(dimy), patch:size(dimx)
   local maxH, maxW = round(h*maxscale), round(w*maxscale)
   if (maxH == h) and (maxW == w) then
      return patch
   else
      local scaleH = torch.random(h, maxH)
      local scaleW = torch.random(w, maxW)
      if patch:dim() == 3 then
	 scaleup_out:typeAs(patch):resize(patch:size(1), scaleH, scaleW)
      else
	 scaleup_out:typeAs(patch):resize(patch:size(1), patch:size(2), scaleH, scaleW)
      end
      return image.scale(flatten3d(scaleup_out), flatten3d(patch), mode)
   end
end

local rotate_out = torch.Tensor()
local function rotate(patch, thetamax, mode)
   mode = mode or 'bilinear'
   assert(thetamax >= 0)
   if thetamax == 0 then
      return patch
   else
      local theta = torch.uniform(-thetamax, thetamax)
      rotate_out:typeAs(patch):resizeAs(patch)
      return image.rotate(flatten3d(rotate_out), flatten3d(patch), theta, mode)
   end
end

local function subtractMean(patch, mean)
    if mean[1] == 0 and mean[2] == 0 and mean[3] == 0 then 
	return patch
    end
    for i = 1,3 do
	patch[{{},{i},{},{}}]:add(-mean[i])
    end
    return patch
end

local function RGBtoBGR(patch, rgb2bgr)
    if rgb2bgr then
    	local tmp = patch[{{},{1},{},{}}]:clone()
	patch[{{},{1},{},{}}] = patch[{{},{3},{},{}}]
	patch[{{},{3},{},{}}] = tmp
    end
    return patch
end

local input2_out = torch.Tensor()
function AugmentDatasource:nextBatch(batchSize, set)
   local input, target = self.datasource:nextBatch(batchSize, set)
   local height, width
   if UsingResize then
   	    height = self.params.resize[1]
        width =  self.params.resize[2]
   else 
	    height = self.params.crop[1]
	    width = self.params.crop[2]
   end
   if input:dim() == 4 then
          input2_out:resize(batchSize, input:size(2),
			height, width)
   else
	  input2_out:resize(batchSize, input:size(2), input:size(3),
			height, width)
   end
   for i = 1, batchSize do
      local x = input[i]
      x = flip(x, self.params.flip)
      x = rotate(x, self.params.rotate)
      x = scaleup(x, self.params.scaleup)
      x = crop(x, self.params.crop[1], self.params.crop[2],
	       self.params.cropMinimumMotion, self.params.cropMinimumMotionNTries)
      x = subtractMean(x, self.params.mean)
      x = RGBtoBGR(x, self.params.rgb2bgr)
      if UsingResize then x = resize(x, self.params.resize) end
      input2_out[i]:copy(x)
   end
   return self:typeResults(input2_out, target)
end

--This has NO data augmentation (you can't iterate over augmented data, it's infinite)
local input3_out = torch.Tensor()
function AugmentDatasource:orderedIterator(batchSize, set)
   local it = self.datasource:orderedIterator(batchSize, set)
   return function()
      local input, label = it()
      if input ~= nil then
        local height, width
   if UsingResize then
   	    height = self.params.resize[1]
        width =  self.params.resize[2]
   else 
	    height = self.params.crop[1]
	    width = self.params.crop[2]
   end
   if input:dim() == 4 then
          input3_out:resize(batchSize, input:size(2), height, width)
   else
	      input3_out:resize(batchSize, input:size(2), input:size(3), height, width)
   end
   for i = 1, batchSize do
      local x = input[i]
      x = scaleup(x, self.params.scaleup)
      x = crop(x, self.params.crop[1], self.params.crop[2],
	       self.params.cropMinimumMotion, self.params.cropMinimumMotionNTries)
      x = subtractMean(x, self.params.mean)
      x = RGBtoBGR(x, self.params.rgb2bgr)
      if UsingResize then x = resize(x, self.params.resize) end
      input3_out[i]:copy(x)
   end
	    return self:typeResults(input3_out, label)
      else
	    return nil
      end
   end
end
