# Image Provider
since kivy rely on making texture and blit something to it
and texture becomes VkImage we should be able to share same VkImage between
Kivy Texture and a Skia Node to load images by it unto the texture
instead of this cpu blit that kivy does...

# Svg Provider

same deal as Image

# Text Provider

i guess same as the other 2...



# general notes 

skia node is already setup to be inited by some VkImage SOOOO WE SHOULD HAVE TO START CHANGE ANYTHING IN THE SKIA PART OF THING

SO DONT START BY CHANGING BEHAVIOR OF THAT NODE... 

IT IS EXTREMELY IMPORTANT THAT THIS KIVY PART ABSOLUTELY HAVE NO EFFECT ON HOW NUCLEANTUI ITSELF RUNS
THIS CANT BE STRESSED OUT ENOUGH... 


AND FOR GOD SAKE DONT START TRY ALL KINDS OF CYTHON STUFF THAT AINT NEEDED
ALWAYS TRY SOLVE IT ON SWIFT SIDE FIRST, SOOO KIVY / CYTHON NEEDS TODO AS LITTLE AS POSSIBLE
ITS ALSO SWIFT SIDE THAT HAS THE REAL CONTROL WITH SHARING VKIMAGE BETWEEN BOTH KIVY TRXTURE AND SKIA NODE...