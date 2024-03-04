def convert_coordinates(input_coordinates):
    result = []

    for i in range(len(input_coordinates) - 1):
        start_loc = input_coordinates[i]
        end_loc = input_coordinates[i + 1]

        result.append({
            'start_loc': [start_loc[0], start_loc[1]],
            'end_loc': [end_loc[0], end_loc[1]],
        })

    return result
