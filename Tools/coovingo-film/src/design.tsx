import React from "react";
import {
  AbsoluteFill,
  CanvasImage,
  Interactive,
  Easing,
  interpolate,
  useCurrentFrame,
  staticFile,
} from "remotion";
import { Video } from "@remotion/media";
export const media = (n: string) => staticFile(`media/${n}`);
export const clamp = {
  extrapolateLeft: "clamp",
  extrapolateRight: "clamp",
} as const;
export const ease = Easing.bezier(0.22, 1, 0.36, 1);
export const Paper: React.FC<{
  children: React.ReactNode;
  background?: string;
  dark?: boolean;
}> = ({ children, background = "bg-desk.jpg", dark = false }) => {
  const f = useCurrentFrame();
  return (
    <AbsoluteFill
      style={{
        background: dark ? "#162b2a" : "#e9e2d3",
        color: dark ? "#fffaf0" : "#163444",
        overflow: "hidden",
      }}
    >
      <CanvasImage
        src={media(background)}
        style={{
          position: "absolute",
          width: "100%",
          height: "100%",
          objectFit: "cover",
          scale: interpolate(f, [0, 420], [1.13, 1.04], clamp),
          translate: interpolate(
            f,
            [0, 420],
            ["-12px 10px", "12px -10px"],
            clamp,
          ),
        }}
      />
      <AbsoluteFill
        style={{
          background: dark
            ? "linear-gradient(180deg,#082329db 0%,#09232266 45%,#071c26b0 100%)"
            : "linear-gradient(120deg,#fffaf0d9 0%,#f7f0e589 55%,#d5e6e577 100%)",
        }}
      />
      <AbsoluteFill
        style={{
          background:
            "radial-gradient(ellipse at 0% 40%,#f6da9830,transparent 70%)",
          mixBlendMode: "screen",
        }}
      />
      {children}
    </AbsoluteFill>
  );
};
export const Headline: React.FC<{
  children: React.ReactNode;
  center?: boolean;
}> = ({ children, center = false }) => {
  const f = useCurrentFrame();
  return (
    <Interactive.Div
      name="Scene headline"
      style={{
        position: "absolute",
        top: 132,
        left: 84,
        right: 80,
        fontSize: 82,
        fontWeight: 500,
        letterSpacing: -2,
        lineHeight: 1.25,
        textAlign: center ? "center" : "left",
        opacity: interpolate(f, [8, 40], [0, 1], clamp),
        translate: interpolate(f, [0, 65], ["0px 26px", "0px 0px"], {
          ...clamp,
          easing: ease,
        }),
      }}
    >
      {children}
    </Interactive.Div>
  );
};
export const NativeScreen: React.FC<{
  file: string;
  video?: boolean;
  x?: number;
  y?: number;
  width?: number;
  angle?: number;
  delay?: number;
}> = ({
  file,
  video = false,
  x = 190,
  y = 310,
  width = 700,
  angle = 0,
  delay = 10,
}) => {
  const f = useCurrentFrame();
  return (
    <Interactive.Div
      name="Intact native product screen"
      style={{
        position: "absolute",
        left: x,
        top: y,
        width,
        padding: 6,
        borderRadius: 48,
        background: "linear-gradient(135deg,#ffffff,#9ca9ad 48%,#edf2f0)",
        boxShadow: "0 45px 85px #0b242b45,0 6px 14px #051f2420",
        opacity: interpolate(f, [delay, delay + 30], [0, 1], clamp),
        translate: interpolate(
          f,
          [delay, delay + 80],
          ["0px 100px", "0px 0px"],
          { ...clamp, easing: ease },
        ),
        rotate: interpolate(
          f,
          [delay, delay + 160, 420],
          [`${angle + 1.4}deg`, `${angle}deg`, `${angle - 0.6}deg`],
          { ...clamp, easing: ease },
        ),
      }}
    >
      <div style={{ borderRadius: 42, overflow: "hidden", lineHeight: 0 }}>
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
  );
};
export const FeatureRail: React.FC<{
  items: string[];
  x: number;
  y: number;
  width?: number;
  dark?: boolean;
  delay?: number;
}> = ({ items, x, y, width = 230, dark = false, delay = 65 }) => {
  const f = useCurrentFrame();
  return (
    <div style={{ position: "absolute", left: x, top: y, width }}>
      {items.map((text, i) => (
        <Interactive.Div
          key={text}
          name={`Learning detail ${text}`}
          style={{
            marginBottom: 74,
            whiteSpace: "pre-line",
            paddingTop: 20,
            borderTop: `1px solid ${dark ? "#f0dfb480" : "#31576555"}`,
            fontSize: 35,
            lineHeight: 1.55,
            letterSpacing: 1,
            color: dark ? "#fff2d4" : "#244b59",
            opacity: interpolate(
              f,
              [delay + i * 38, delay + 30 + i * 38],
              [0, 1],
              clamp,
            ),
            translate: interpolate(
              f,
              [delay + i * 38, delay + 65 + i * 38],
              ["0px 24px", "0px 0px"],
              { ...clamp, easing: ease },
            ),
          }}
        >
          {text}
        </Interactive.Div>
      ))}
    </div>
  );
};
