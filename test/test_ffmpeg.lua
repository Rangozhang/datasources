require 'ffmpeg'

path = "../../../dataset/UCF101/videos/ApplyEyeMakeup/v_ApplyEyeMakeup_g01_c01.avi"

vid = ffmpeg.Video(path)
print(vid[1][1])

--[[
i = vid:forward()
print(i)
io.read()
i = vid:forward()
print(i)
--]]
