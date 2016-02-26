package.path = "../../?.lua;" .. package.path
require 'datasources.ucf101'
require 'datasources.augment'
require 'image'

local params = {}
params.nInputFrames = 5
params.datapath = '/home/yu/ws_torch/dataset/UCF101/videos'
params.listpath = '/home/yu/ws_torch/dataset/UCF101/ucfTrainTestlist'

datasource = AugmentDatasource(UCF101Datasource(params), {crop={120, 120}})

batch, label = datasource:nextBatch(8, 'train')
print{batch}
itorch.image({batch[1][1], batch[1][2], batch[2][1], batch[2][2]})
io.read()
torch.setnumthreads(2)

--[[
image.display({image=batch[1][1], legend=1})
image.display({image=batch[1][2], legend=2})
image.display({image=batch[1][3], legend=3})
image.display({image=batch[1][4], legend=4})
image.display({image=batch[1][5], legend=5})
image.display({image=batch[2][1], legend=1})
image.display({image=batch[2][2], legend=2})
--]]


require 'datasources.thread'
require 'cutorch'
datasource = ThreadedDatasource(
   function()
      package.path = "../../?.lua;" .. package.path
      require 'datasources.ucf101'
      require 'datasources.augment'
      return AugmentDatasource(UCF101Datasource(params), {crop={32,32}, mean={123.68, 116.779, 103.939}, rgb2bgr=true})
   end, {nDonkeys=3})
datasource:cuda()
--[[
timer = torch.Timer()
for i = 1, 10 do
   batch, label = datasource:nextBatch(4, 'train')
   print{batch}
end
print(timer:time())
--]]
--[[
i = 0
for batch, label in datasource:orderedIterator(16, 'test') do
   i = i + 1
   print(i)
   print(#batch)
   print(#label)
   if i == 100 then
      break
   end
end
--]]

print("ok")
