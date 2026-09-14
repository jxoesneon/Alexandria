from PIL import Image
import piexif
import io

img = Image.new('RGB', (1920, 1080), color='blue')

zeroth_ifd = {
    piexif.ImageIFD.Make: u"Canon",
    piexif.ImageIFD.Model: u"EOS R5",
    piexif.ImageIFD.DateTime: u"2023:05:01 12:00:00",
    piexif.ImageIFD.Artist: u"Alexandria",
    piexif.ImageIFD.ImageWidth: 1920,
    piexif.ImageIFD.ImageLength: 1080,
}

exif_ifd = {
    piexif.ExifIFD.DateTimeOriginal: u"2023:05:01 12:00:00",
    piexif.ExifIFD.ISOSpeedRatings: 400,
    piexif.ExifIFD.FNumber: (28, 10),
    piexif.ExifIFD.ExposureTime: (1, 250),
    piexif.ExifIFD.FocalLength: (50, 1),
    piexif.ExifIFD.PixelXDimension: 1920,
    piexif.ExifIFD.PixelYDimension: 1080,
}

gps_ifd = {
    piexif.GPSIFD.GPSLatitude: ((37, 1), (46, 1), (29, 1)),
    piexif.GPSIFD.GPSLatitudeRef: 'N',
    piexif.GPSIFD.GPSLongitude: ((122, 1), (25, 1), (10, 1)),
    piexif.GPSIFD.GPSLongitudeRef: 'W',
}

exif_dict = {"0th": zeroth_ifd, "Exif": exif_ifd, "GPS": gps_ifd}
exif_bytes = piexif.dump(exif_dict)

buf = io.BytesIO()
img.save(buf, format="JPEG", exif=exif_bytes)
data = buf.getvalue()

with open("test/fixtures/sample_exif.jpg", "wb") as f:
    f.write(data)
print(f"Generated {len(data)} bytes")
