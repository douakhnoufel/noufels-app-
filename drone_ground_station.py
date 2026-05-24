import cv2
import time
import argparse
from ultralytics import YOLO

def run_ground_station(stream_url, model_path, confidence):
    print(f"--- PlantGuard Drone Ground Station ---")
    print(f"Loading Model: {model_path}")
    
    # Load YOLOv8 Model
    try:
        model = YOLO(model_path)
    except Exception as e:
        print(f"Error loading model: {e}")
        return

    print(f"Connecting to Stream: {stream_url}")
    cap = cv2.VideoCapture(stream_url)

    if not cap.isOpened():
        print("Error: Could not open video stream. Ensure your drone is streaming to RTMP.")
        return

    print("Stream Connected. Press 'q' on the monitor window to exit.")
    
    # Performance tracking
    prev_time = 0

    while True:
        success, frame = cap.read()
        if not success:
            print("Dropped frame or stream ended. Reconnecting...")
            time.sleep(1)
            cap = cv2.VideoCapture(stream_url)
            continue

        # Run YOLOv8 Inference
        results = model(frame, conf=confidence, verbose=False)
        
        # Draw results on frame
        annotated_frame = results[0].plot()

        # Calculate FPS
        curr_time = time.time()
        fps = 1 / (curr_time - prev_time)
        prev_time = curr_time

        # Add Status Overlay
        cv2.putText(annotated_frame, f"FPS: {fps:.1f}", (20, 40), 
                    cv2.FONT_HERSHEY_SIMPLEX, 1, (0, 255, 0), 2)
        cv2.putText(annotated_frame, "DJI MAVIC AIR 2 - LIVE", (20, 80), 
                    cv2.FONT_HERSHEY_SIMPLEX, 0.7, (255, 255, 255), 2)

        # Show the monitor
        cv2.imshow("PlantGuard: Real-Time Drone Monitor", annotated_frame)

        if cv2.waitKey(1) & 0xFF == ord("q"):
            break

    cap.release()
    cv2.destroyAllWindows()

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="PlantGuard Drone Ground Station")
    parser.add_argument("--url", type=str, default="rtmp://localhost/live/drone", help="RTMP/RTSP stream URL")
    parser.add_argument("--model", type=str, default="best.pt", help="Path to best.pt model")
    parser.add_argument("--conf", type=float, default=0.45, help="Confidence threshold")

    args = parser.parse_args()
    run_ground_station(args.url, args.model, args.conf)
