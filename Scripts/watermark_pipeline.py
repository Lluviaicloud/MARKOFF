#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import math
import os
import sys
from dataclasses import dataclass

import cv2
import numpy as np


@dataclass
class AnalysisResult:
    rects: list[tuple[int, int, int, int]]
    mask: np.ndarray
    confidence: float


def normalize_map(values: np.ndarray) -> np.ndarray:
    values = values.astype(np.float32)
    min_value = float(values.min())
    max_value = float(values.max())
    if math.isclose(min_value, max_value):
        return np.zeros_like(values, dtype=np.float32)
    return (values - min_value) / (max_value - min_value)


def sample_frames(input_path: str, max_samples: int = 12, max_dimension: int = 960) -> tuple[list[np.ndarray], tuple[int, int], float]:
    capture = cv2.VideoCapture(input_path)
    if not capture.isOpened():
        raise RuntimeError("No se pudo abrir el video de entrada.")

    frame_count = int(capture.get(cv2.CAP_PROP_FRAME_COUNT))
    width = int(capture.get(cv2.CAP_PROP_FRAME_WIDTH))
    height = int(capture.get(cv2.CAP_PROP_FRAME_HEIGHT))
    if frame_count <= 0 or width <= 0 or height <= 0:
        raise RuntimeError("No se pudo leer la metadata del video.")

    sample_count = max(3, min(frame_count, max_samples))
    indices = np.linspace(0, frame_count - 1, sample_count, dtype=np.int32)

    scale = 1.0
    largest_dimension = max(width, height)
    if largest_dimension > max_dimension:
        scale = max_dimension / float(largest_dimension)

    frames: list[np.ndarray] = []
    for index in np.unique(indices):
        capture.set(cv2.CAP_PROP_POS_FRAMES, int(index))
        ok, frame = capture.read()
        if not ok:
            continue
        if scale != 1.0:
            frame = cv2.resize(frame, None, fx=scale, fy=scale, interpolation=cv2.INTER_AREA)
        frames.append(frame)

    capture.release()

    if len(frames) < 3:
        raise RuntimeError("No se pudieron muestrear suficientes frames para detectar la marca.")

    return frames, (width, height), scale


def compute_feature_maps(
    frames: list[np.ndarray],
) -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    gray_frames = [cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY) for frame in frames]
    gray_stack = np.stack(gray_frames).astype(np.float32)

    mean_gray = gray_stack.mean(axis=0)
    std_gray = gray_stack.std(axis=0)
    stability = 1.0 - normalize_map(std_gray)

    edge_stack = np.stack([cv2.Canny(gray.astype(np.uint8), 80, 160) for gray in gray_frames]).astype(np.float32)
    edge_mean = normalize_map(edge_stack.mean(axis=0))

    blurred = cv2.GaussianBlur(mean_gray, (0, 0), sigmaX=8.0)
    contrast = normalize_map(np.abs(mean_gray - blurred))
    brightness = normalize_map(mean_gray)

    height, width = mean_gray.shape
    yy, xx = np.indices((height, width), dtype=np.float32)
    edge_distance = np.minimum.reduce([
        xx / max(width - 1, 1),
        yy / max(height - 1, 1),
        (width - 1 - xx) / max(width - 1, 1),
        (height - 1 - yy) / max(height - 1, 1),
    ])
    corner_bias = 1.0 - np.clip(edge_distance * 3.0, 0.0, 1.0)
    edge_bias = 1.0 - np.clip(edge_distance * 4.0, 0.0, 1.0)
    lower_bias = yy / max(height - 1, 1)

    combined = (0.26 * stability) + (0.18 * edge_mean) + (0.16 * contrast) + (0.20 * brightness) + (0.20 * corner_bias)
    return (
        combined.astype(np.float32),
        stability.astype(np.float32),
        edge_mean.astype(np.float32),
        contrast.astype(np.float32),
        brightness.astype(np.float32),
        edge_bias.astype(np.float32),
        lower_bias.astype(np.float32),
    )


def component_candidates(
    score_map: np.ndarray,
    brightness_map: np.ndarray,
    edge_bias: np.ndarray,
    lower_bias: np.ndarray,
) -> list[tuple[int, int, int, int, float, np.ndarray]]:
    search_score = (
        score_map * (0.50 + (0.34 * edge_bias) + (0.16 * lower_bias))
        + (0.14 * brightness_map)
        + (0.12 * lower_bias * edge_bias)
    )
    threshold = float(np.percentile(search_score, 98.7))
    binary = (search_score >= threshold).astype(np.uint8) * 255
    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (7, 7))
    binary = cv2.morphologyEx(binary, cv2.MORPH_CLOSE, kernel, iterations=2)
    binary = cv2.morphologyEx(binary, cv2.MORPH_OPEN, kernel, iterations=1)

    count, labels, stats, _ = cv2.connectedComponentsWithStats(binary)
    frame_area = search_score.shape[0] * search_score.shape[1]
    candidates: list[tuple[int, int, int, int, float, np.ndarray]] = []

    for label in range(1, count):
        x, y, width, height, area = stats[label]
        if area < max(24, frame_area * 0.00008):
            continue
        if area > frame_area * 0.025:
            continue

        component_mask = labels == label
        component_score = float(search_score[component_mask].mean())
        brightness_score = float(brightness_map[component_mask].mean())
        edge_score = float(edge_bias[component_mask].mean())
        lower_score = float(lower_bias[component_mask].mean())
        center_x = x + (width / 2.0)
        center_y = y + (height / 2.0)
        margin_x = min(center_x / max(search_score.shape[1], 1), 1.0 - center_x / max(search_score.shape[1], 1))
        margin_y = min(center_y / max(search_score.shape[0], 1), 1.0 - center_y / max(search_score.shape[0], 1))
        corner_bonus = 1.0 - min(margin_x, margin_y) * 2.0
        area_penalty = min(1.0, math.sqrt(area / max(frame_area * 0.003, 1.0)))
        final_score = (
            component_score * 0.45
            + brightness_score * 0.20
            + edge_score * 0.16
            + lower_score * 0.12
            + corner_bonus * 0.22
            - area_penalty * 0.10
        )
        candidates.append((x, y, width, height, final_score, component_mask))

    candidates.sort(key=lambda item: item[4], reverse=True)
    return candidates


def grow_mask_in_rect(score_map: np.ndarray, rect: tuple[int, int, int, int]) -> np.ndarray:
    x, y, width, height = rect
    mask = np.zeros(score_map.shape, dtype=np.uint8)
    roi = score_map[y:y + height, x:x + width]
    if roi.size == 0:
        return mask

    roi_threshold = max(float(np.percentile(roi, 65.0)), float(roi.mean() + (roi.std() * 0.1)))
    roi_mask = (roi >= roi_threshold).astype(np.uint8) * 255
    if int(roi_mask.sum()) < max(12, int(width * height * 0.04)):
        roi_mask[:, :] = 255

    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5))
    roi_mask = cv2.morphologyEx(roi_mask, cv2.MORPH_CLOSE, kernel, iterations=2)
    roi_mask = cv2.dilate(roi_mask, kernel, iterations=1)
    mask[y:y + height, x:x + width] = roi_mask
    return mask


def build_rect_mask(mask_shape: tuple[int, int], rect: tuple[int, int, int, int]) -> np.ndarray:
    x, y, width, height = rect
    mask = np.zeros(mask_shape, dtype=np.uint8)
    mask[y:y + height, x:x + width] = 255
    return mask


CORNER_BRIGHTNESS_EVIDENCE_MIN = 0.20
CORNER_EDGE_EVIDENCE_MIN = 0.15


def detect_corner_watermark(
    score_map: np.ndarray,
    stability_map: np.ndarray,
    brightness_map: np.ndarray,
    edge_mean: np.ndarray,
    edge_bias: np.ndarray,
    lower_bias: np.ndarray,
) -> AnalysisResult | None:
    candidates = component_candidates(score_map, brightness_map, edge_bias, lower_bias)
    if not candidates:
        return None

    selected: tuple[int, int, int, int, float, np.ndarray] | None = None
    for candidate in candidates:
        _, _, _, _, _, candidate_mask = candidate
        brightness_evidence = float(brightness_map[candidate_mask].mean())
        edge_evidence = float(edge_mean[candidate_mask].mean())
        if brightness_evidence >= CORNER_BRIGHTNESS_EVIDENCE_MIN or edge_evidence >= CORNER_EDGE_EVIDENCE_MIN:
            selected = candidate
            break

    if selected is None:
        return None

    x, y, width, height, component_score, component_mask = selected
    padded_x = max(0, x - 10)
    padded_y = max(0, y - 10)
    padded_w = min(score_map.shape[1] - padded_x, max(width + 20, 48))
    padded_h = min(score_map.shape[0] - padded_y, max(height + 20, 48))
    rect = (padded_x, padded_y, padded_w, padded_h)

    mask = build_rect_mask(score_map.shape, rect)
    refined_mask = grow_mask_in_rect(score_map, rect)
    mask[refined_mask > 0] = 255
    mask[component_mask] = 255
    mask = cv2.dilate(mask, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (7, 7)), iterations=2)

    stability_score = float(stability_map[mask > 0].mean()) if np.any(mask > 0) else 0.0
    confidence = float(np.clip(component_score * 0.68 + stability_score * 0.32, 0.0, 1.0))
    return AnalysisResult(rects=[rect], mask=mask, confidence=confidence)


def detect_top_right_overlay(
    stability_map: np.ndarray,
    edge_mean: np.ndarray,
    contrast: np.ndarray,
    brightness_map: np.ndarray,
) -> AnalysisResult | None:
    height, width = brightness_map.shape
    x0 = int(width * 0.52)
    y1 = int(height * 0.34)

    score = (
        0.50 * brightness_map
        + 0.30 * stability_map
        + 0.12 * edge_mean
        + 0.08 * contrast
    )

    roi = score[0:y1, x0:width]
    if roi.size == 0:
        return None

    threshold = max(float(np.percentile(roi, 99.0)), float(roi.mean() + roi.std() * 1.1))
    binary = (roi >= threshold).astype(np.uint8) * 255
    binary = cv2.morphologyEx(
        binary,
        cv2.MORPH_CLOSE,
        cv2.getStructuringElement(cv2.MORPH_RECT, (7, 3)),
        iterations=1,
    )
    binary = cv2.dilate(binary, cv2.getStructuringElement(cv2.MORPH_RECT, (3, 3)), iterations=1)

    count, labels, stats, _ = cv2.connectedComponentsWithStats(binary)
    candidates: list[tuple[int, int, int, int, float, np.ndarray]] = []

    for label in range(1, count):
        rx, ry, rw, rh, area = stats[label]
        if area < 16:
            continue
        width_ratio = rw / max(width, 1)
        height_ratio = rh / max(height, 1)
        if width_ratio > 0.18:
            continue
        if height_ratio > 0.05:
            continue

        component_mask = labels == label
        component_score = float(roi[component_mask].mean())
        candidates.append((rx, ry, rw, rh, component_score, component_mask))

    if not candidates:
        return None

    candidates.sort(key=lambda item: item[4], reverse=True)
    best_score = candidates[0][4]

    roi_mask = np.zeros(roi.shape, dtype=np.uint8)
    selected = 0
    for rx, ry, rw, rh, component_score, component_mask in candidates:
        actual_x = x0 + rx
        actual_y = ry
        if component_score < best_score * 0.30:
            continue
        if actual_x < int(width * 0.55):
            continue
        if actual_y < int(height * 0.14) or actual_y > int(height * 0.31):
            continue
        roi_mask[component_mask] = 255
        selected += 1

    if selected == 0:
        return None

    roi_mask = cv2.morphologyEx(
        roi_mask,
        cv2.MORPH_CLOSE,
        cv2.getStructuringElement(cv2.MORPH_RECT, (35, 5)),
        iterations=1,
    )
    roi_mask = cv2.dilate(roi_mask, cv2.getStructuringElement(cv2.MORPH_RECT, (7, 3)), iterations=1)

    ys, xs = np.where(roi_mask > 0)
    if ys.size == 0 or xs.size == 0:
        return None

    min_x = int(xs.min())
    max_x = int(xs.max())
    min_y = int(ys.min())
    max_y = int(ys.max())
    pad_x = 10
    pad_y = 8
    rect = (
        max(0, x0 + min_x - pad_x),
        max(0, min_y - pad_y),
        min(width - max(0, x0 + min_x - pad_x), (max_x - min_x + 1) + pad_x * 2),
        min(height - max(0, min_y - pad_y), (max_y - min_y + 1) + pad_y * 2),
    )

    mask = np.zeros(brightness_map.shape, dtype=np.uint8)
    mask[0:y1, x0:width][roi_mask > 0] = 255
    confidence = float(np.clip(best_score, 0.0, 1.0))
    return AnalysisResult(rects=[rect], mask=mask, confidence=confidence)


def merge_analyses(analyses: list[AnalysisResult]) -> AnalysisResult:
    combined_mask = np.zeros_like(analyses[0].mask)
    rects: list[tuple[int, int, int, int]] = []
    confidences: list[float] = []

    for analysis in analyses:
        combined_mask[analysis.mask > 0] = 255
        rects.extend(analysis.rects)
        confidences.append(analysis.confidence)

    return AnalysisResult(
        rects=rects,
        mask=combined_mask,
        confidence=float(np.clip(sum(confidences) / max(len(confidences), 1), 0.0, 1.0)),
    )


def detect_watermark(frames: list[np.ndarray]) -> AnalysisResult:
    score_map, stability_map, edge_mean, contrast, brightness_map, edge_bias, lower_bias = compute_feature_maps(frames)
    analyses: list[AnalysisResult] = []

    corner_result = detect_corner_watermark(score_map, stability_map, brightness_map, edge_mean, edge_bias, lower_bias)
    if corner_result is not None:
        analyses.append(corner_result)

    top_right_result = detect_top_right_overlay(stability_map, edge_mean, contrast, brightness_map)
    if top_right_result is not None:
        analyses.append(top_right_result)

    if not analyses:
        raise RuntimeError("No se encontro una region candidata para la marca de agua.")

    return merge_analyses(analyses)


def rect_to_pixels(rect_string: str, frame_shape: tuple[int, int, int]) -> tuple[int, int, int, int]:
    parts = [float(value) for value in rect_string.split(",")]
    if len(parts) != 4:
        raise RuntimeError("El rectangulo manual no tiene el formato esperado.")

    height, width = frame_shape[:2]
    x = max(0, min(width - 1, int(round(parts[0] * width))))
    y = max(0, min(height - 1, int(round(parts[1] * height))))
    rect_width = max(1, min(width - x, int(round(parts[2] * width))))
    rect_height = max(1, min(height - y, int(round(parts[3] * height))))
    return x, y, rect_width, rect_height


def manual_analysis(frames: list[np.ndarray], rect_string: str) -> AnalysisResult:
    score_map, _, _, _, _, _, _ = compute_feature_maps(frames)
    rect = rect_to_pixels(rect_string, frames[0].shape)
    mask = grow_mask_in_rect(score_map, rect)
    confidence = float(np.clip(score_map[mask > 0].mean() if np.any(mask > 0) else 0.35, 0.0, 1.0))
    return AnalysisResult(rects=[rect], mask=mask, confidence=confidence)


def resize_mask_to_original(mask: np.ndarray, original_size: tuple[int, int]) -> np.ndarray:
    original_width, original_height = original_size
    return cv2.resize(mask, (original_width, original_height), interpolation=cv2.INTER_NEAREST)


def normalized_rect(rect: tuple[int, int, int, int], frame_shape: tuple[int, int, int]) -> dict[str, float]:
    height, width = frame_shape[:2]
    x, y, rect_width, rect_height = rect
    return {
        "x": x / float(width),
        "y": y / float(height),
        "width": rect_width / float(width),
        "height": rect_height / float(height),
    }


def write_progress(progress_file: str | None, fraction: float) -> None:
    if not progress_file:
        return
    try:
        with open(progress_file, "w", encoding="utf-8") as handle:
            handle.write(f"{min(max(fraction, 0.0), 1.0):.4f}")
    except OSError:
        pass


def process_video(
    input_path: str,
    output_video: str,
    analysis: AnalysisResult,
    original_size: tuple[int, int],
    progress_file: str | None = None,
) -> None:
    mask = resize_mask_to_original(analysis.mask, original_size)

    capture = cv2.VideoCapture(input_path)
    if not capture.isOpened():
        raise RuntimeError("No se pudo reabrir el video para procesarlo.")

    fps = capture.get(cv2.CAP_PROP_FPS)
    fps = fps if fps and fps > 0 else 30.0
    width = int(capture.get(cv2.CAP_PROP_FRAME_WIDTH))
    height = int(capture.get(cv2.CAP_PROP_FRAME_HEIGHT))
    total_frames = int(capture.get(cv2.CAP_PROP_FRAME_COUNT))

    os.makedirs(os.path.dirname(output_video), exist_ok=True)
    writer = cv2.VideoWriter(
        output_video,
        cv2.VideoWriter_fourcc(*"mp4v"),
        fps,
        (width, height),
    )
    if not writer.isOpened():
        raise RuntimeError("No se pudo crear el video procesado.")

    write_progress(progress_file, 0.0)
    processed = 0
    while True:
        ok, frame = capture.read()
        if not ok:
            break

        inpainted = cv2.inpaint(frame, mask, 7, cv2.INPAINT_TELEA)
        writer.write(inpainted)
        processed += 1

        if total_frames > 0 and (processed % 3 == 0 or processed == total_frames):
            write_progress(progress_file, processed / total_frames)

    capture.release()
    writer.release()
    write_progress(progress_file, 1.0)


def emit_ok(result: AnalysisResult, frame_shape: tuple[int, int, int]) -> None:
    primary_rect = result.rects[0]
    payload = {
        "status": "ok",
        "rect": normalized_rect(primary_rect, frame_shape),
        "regions": [normalized_rect(rect, frame_shape) for rect in result.rects],
        "confidence": round(result.confidence, 4),
    }
    print(json.dumps(payload))


def emit_error(message: str) -> None:
    print(json.dumps({"status": "error", "message": message}))


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)

    detect_parser = subparsers.add_parser("detect")
    detect_parser.add_argument("--input", required=True)

    process_parser = subparsers.add_parser("process")
    process_parser.add_argument("--input", required=True)
    process_parser.add_argument("--output-video", required=True)
    process_parser.add_argument("--mode", choices=("auto", "manual"), required=True)
    process_parser.add_argument("--rect")
    process_parser.add_argument("--progress-file")

    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()

    try:
        frames, original_size, _ = sample_frames(args.input)
        if args.command == "detect":
            result = detect_watermark(frames)
            emit_ok(result, frames[0].shape)
            return 0

        if args.mode == "manual":
            if not args.rect:
                raise RuntimeError("El modo manual requiere un rectangulo normalizado.")
            result = manual_analysis(frames, args.rect)
        else:
            result = detect_watermark(frames)

        process_video(
            args.input,
            args.output_video,
            result,
            original_size,
            progress_file=getattr(args, "progress_file", None),
        )
        emit_ok(result, frames[0].shape)
        return 0
    except Exception as error:
        emit_error(str(error))
        return 1


if __name__ == "__main__":
    sys.exit(main())
