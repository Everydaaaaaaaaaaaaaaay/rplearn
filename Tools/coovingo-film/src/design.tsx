import React from "react";
import {
  AbsoluteFill,
  CanvasImage,
  Interactive,
  Easing,
  interpolate,
  staticFile,
  useCurrentFrame,
} from "remotion";
import { Video } from "@remotion/media";
export const media = (name: string) => staticFile(`media/${name}`);
export const clamp = {
  extrapolateLeft: "clamp",
  extrapolateRight: "clamp",
} as const;
export const ease = Easing.bezier(0.22, 1, 0.36, 1);
export const Paper: React.FC<{ children: React.ReactNode }> = ({
  children,
}) => (
  <AbsoluteFill
    style={{ background: "#f8fafb", color: "#142d40", overflow: "hidden" }}
  >
    {children}
  </AbsoluteFill>
);
export const LearningScene: React.FC<{
  title: string;
  file: string;
  video?: boolean;
}> = ({ title, file, video = false }) => {
  const f = useCurrentFrame();
  const enter = interpolate(f, [0, 66], [0, 1], { ...clamp, easing: ease });
  return (
    <Paper>
      <Interactive.Div
        name="Single feature headline"
        style={{
          position: "absolute",
          top: 120,
          left: 80,
          right: 80,
          textAlign: "center",
          fontSize: 76,
          fontWeight: 500,
          letterSpacing: -2,
          lineHeight: 1.25,
          opacity: interpolate(f, [8, 38], [0, 1], clamp),
          transform: `translateY(${(1 - enter) * 20}px)`,
        }}
      >
        {title}
      </Interactive.Div>
      <Interactive.Div
        name="Complete native screen"
        style={{
          position: "absolute",
          left: 190,
          top: 300,
          width: 700,
          padding: 5,
          borderRadius: 49,
          background: "#d6dee3",
          boxShadow: "0 24px 65px #18354b18",
          transform: `translateY(${(1 - enter) * 48}px)`,
          opacity: interpolate(f, [0, 30], [0, 1], clamp),
        }}
      >
        <div style={{ borderRadius: 44, overflow: "hidden", lineHeight: 0 }}>
          {video ? (
            <Video
              src={media(file)}
              trimBefore={360}
              muted
              style={{ width: "100%", display: "block" }}
            />
          ) : (
            <CanvasImage
              src={media(file)}
              style={{ width: "100%", display: "block" }}
            />
          )}
        </div>
      </Interactive.Div>
    </Paper>
  );
};
