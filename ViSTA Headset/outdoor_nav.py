import requests
import math
from gpiozero import PWMOutputDevice
import py_qmc5883l
import time
from polyline import decode
from util import convert_coordinates

LEFT = 27
RIGHT = 20
BOTH = 0

motor_right = PWMOutputDevice(RIGHT)
motor_left = PWMOutputDevice(LEFT)

def vibrate(side, intensity, duration):
    if side == RIGHT:
        motor_right.value=intensity
        time.sleep(duration)
        motor_right.value = 0.0
    elif side == LEFT:
        motor_left.value = intensity
        time.sleep(duration)
        motor_left.value = 0.0
    elif side == BOTH:
        motor_left.value = intensity
        motor_right.value = intensity
        time.sleep(duration)
        motor_left.value = 0.0
        motor_right.value = 0.0

def adjust_bearing_angle(bearing_angle):

    corrected_bearing = (bearing_angle + 180) % 360

    if corrected_bearing <= 180:
        corrected_bearing = 180 - corrected_bearing
    else:
        corrected_bearing = 540 - corrected_bearing

    return corrected_bearing

def get_current_heading():
    sensor = py_qmc5883l.QMC5883L()
    sensor.calibration = [[1.013844943528671, 0.034764285583721855, 995.075050463388], [0.034764285583721855, 1.087292198024776, -3020.3394988596433], [0.0, 0.0, 1.0]]
    try:
        bearing_angle = sensor.get_bearing()
        adjusted_angle = adjust_bearing_angle(bearing_angle)

    except:
        print("MAG. ERROR HANDLED")
    return float(adjusted_angle)

def get_current_loc():

    url = f"http://10.3.141.61:8080"
    try:
        response = requests.get(url)
        if response.status_code == 200:
            res = response.text.split(",")
            return {"lat": float(res[0]), "lon": float(res[1])}
        else:
            print(f"Error: Unable to fetch data. Status code: {response.status_code}")
    except requests.RequestException as e:
        print(f"Error: {e}")

def haversine_distance(lat1, lon1, lat2, lon2):
    # Radius of the Earth in kilometers
    earth_radius = 6371

    # Convert latitude and longitude from degrees to radians
    lat1 = math.radians(lat1)
    lon1 = math.radians(lon1)
    lat2 = math.radians(lat2)
    lon2 = math.radians(lon2)

    # Haversine formula
    dlat = lat2 - lat1
    dlon = lon2 - lon1
    a = math.sin(dlat / 2)**2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlon / 2)**2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    distance = earth_radius * c

    return distance * 1000

def haversine_heading(lat1, lon1, lat2, lon2):
    # Convert latitude and longitude from degrees to radians
    lat1 = math.radians(lat1)
    lon1 = math.radians(lon1)
    lat2 = math.radians(lat2)
    lon2 = math.radians(lon2)

    # Haversine formula
    dlon = lon2 - lon1
    dlat = lat2 - lat1
    a = (math.sin(dlat / 2))**2 + math.cos(lat1) * math.cos(lat2) * (math.sin(dlon / 2))**2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))

    # Calculate the initial bearing (azimuth)
    y = math.sin(dlon) * math.cos(lat2)
    x = math.cos(lat1) * math.sin(lat2) - math.sin(lat1) * math.cos(lat2) * math.cos(dlon)
    initial_bearing = math.atan2(y, x)
    initial_bearing = math.degrees(initial_bearing)
    compass_bearing = (initial_bearing + 360) % 360

    return compass_bearing

def generate_decimal(value):
    # Define the range boundaries
    lower_bound = 0
    upper_bound = 180

    # Ensure the value is within the range
    # Ensure the value is within the range
    value = max(lower_bound, min(upper_bound, value))

    # Calculate the proximity ratio
    proximity_ratio = (value - lower_bound) / (upper_bound - lower_bound)

    # Generate a decimal between 0.3 and 1 based on the proximity ratio
    generated_decimal = 0.3 + 0.7 * proximity_ratio

    return generated_decimal

def calculate_pwm_intensity(distance, max_distance, k):
    intensity = 1 - math.exp(-k * (max_distance - distance))
    return intensity


def main():

    url = f"http://10.3.141.61:8080/getSysPolyline"
    polyline_ready = False
    while polyline_ready == False:
        try:
            response = requests.get(url)
            if response.status_code == 200:
                res = response.text
                if res != "NA":
                    polyline_ready = True
                else:
                    print("PENDING ROUTE...")
            else:
                print(f"Error: Unable to fetch data. Status code: {response.status_code}")
        except requests.RequestException as e:
            print(f"Error: {e}")

    decoded_polyline = decode(res)
    route = convert_coordinates(decoded_polyline)

    for path in route:
        reached_checkpoint = False
        while reached_checkpoint == False:
            current_loc = get_current_loc()
            distance = haversine_distance(current_loc['lat'], current_loc['lon'], path['end_loc'][0], path['end_loc'][1])

            if distance <= 4:
                with open("checkpoints.txt", "a") as the_file:
                    the_file.write(f"{str(current_loc['lat'])}, {str(current_loc['lon'])}\n")
                reached_checkpoint = True

            #print(path)

            proper_heading = haversine_heading(current_loc['lat'], current_loc['lon'], path['end_loc'][0], path['end_loc'][1])
            current_heading = get_current_heading()

            angle_difference = (proper_heading - current_heading + 180) % 360 - 180
            # print("current: " + str(current_heading))
            # print("proper: " + str(proper_heading))
            # print("diff: " + str(angle_difference))
            # print("distance: " + str(distance))
            ETH = 25
            if angle_difference >= ETH:
                intensity = generate_decimal(abs(angle_difference))
                print("turn right==>>>")
                vibrate(RIGHT, intensity, 0.2)
            elif angle_difference <= -ETH:
                intensity = generate_decimal(abs(angle_difference))
                print("<<<==turn left")
                vibrate(LEFT, intensity, 0.2)
            else:
                print("|==continue==|")

                distance_threshold = 10
                if distance <= distance_threshold:
                    intensity = calculate_pwm_intensity(distance, distance_threshold, 0.3)
                    vibrate(BOTH, intensity, 0.2)
                pass

if __name__ == "__main__":
    main()