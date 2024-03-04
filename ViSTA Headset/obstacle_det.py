
import cv2
import requests
import time
from outdoor_nav import vibrate

LEFT = 27
RIGHT = 20

cap = cv2.VideoCapture(0)

def remove_regions(image):
    # Get the dimensions of the image
    height, width, _ = image.shape

    # Remove the left and right thirds
    left_third = int(width / 3)
    right_third = int(2 * width / 3)
    image = image[:, left_third:right_third]

    # Remove the top third and the bottom fifth
    top_third = int(height / 3)
    bottom_fifth = int(4 * height / 5)
    image = image[top_third:bottom_fifth, :]

    return image

while True:
    ret, frame = cap.read()
    frame = remove_regions(frame)
    frame = cv2.rotate(frame, cv2.ROTATE_180)
    frame = remove_regions(frame)
    _, image_data = cv2.imencode('.jpg', frame)
    image_bytes = image_data.tobytes()

    print("Image captured successfully.")

    url = "http://10.3.141.61:8080/uploadAndEval"

    files = {'my_file': image_bytes}

    # Send the POST request with the image file
    response = requests.post(url, files=files)
    res = response.text
    if res == "left":
        vibrate(LEFT, 0.8, 0.2)
    elif res == "right":
        vibrate(RIGHT, 0.8, 0.2)
    elif res == "stay":
        pass
