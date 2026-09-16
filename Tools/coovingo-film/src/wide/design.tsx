import React from "react";
import {
  AbsoluteFill,
  CanvasImage,
  Interactive,
  interpolate,
  useCurrentFrame,
} from "remotion";
import { Video } from "@remotion/media";
import { media, clamp, ease } from "../design";
export const Canvas: React.FC<{
  children: React.ReactNode;
  dark?: boolean;
  bg?: string;
}> = ({ children, dark = false, bg = "bg-desk.jpg" }) => {
  const f = useCurrentFrame();
  return (
    <AbsoluteFill
      style={{
        overflow: "hidden",
        background: dark ? "#102f36" : "#eee8d9",
        color: dark ? "#fff8e9" : "#173c49",
      }}
    >
      <CanvasImage
        src={media(bg)}
        style={{
          width: "100%",
          height: "100%",
          objectFit: "cover",
          objectPosition: "50% 52%",
          scale: interpolate(f, [0, 540], [1.12, 1.04], clamp),
        }}
      />
      <AbsoluteFill
        style={{
          background: dark
            ? "linear-gradient(100deg,#092d36f5 0%,#0b2933e8 42%,#183a4277 100%)"
            : "linear-gradient(100deg,#fff8ecef 0%,#f8efdded 45%,#e5dfcf9c 100%)",
        }}
      />
      <div
        style={{
          position: "absolute",
          width: 1100,
          height: 1100,
          borderRadius: "50%",
          border: `1px solid ${dark ? "#b6dbd029" : "#26495120"}`,
          left: 980,
          top: 130,
          scale: interpolate(f, [0, 540], [0.97, 1.03], clamp),
        }}
      />
      {children}
    </AbsoluteFill>
  );
};
export const Copy: React.FC<{
  title: string;
  body: string;
  kicker?: string;
  top?: number;
  width?: number;
}> = ({ title, body, kicker, top = 220, width = 920 }) => {
  const f = useCurrentFrame();
  return (
    <Interactive.Div
      name="Landscape story copy"
      style={{
        position: "absolute",
        left: 112,
        top,
        width,
        opacity: interpolate(f, [6, 36], [0, 1], clamp),
        translate: interpolate(f, [0, 65], ["0px 28px", "0px 0px"], {
          ...clamp,
          easing: ease,
        }),
      }}
    >
      {kicker && (
        <div
          style={{
            fontSize: 25,
            letterSpacing: 5,
            opacity: 0.62,
            marginBottom: 34,
          }}
        >
          {kicker}
        </div>
      )}
      <div
        style={{
          fontSize: 88,
          lineHeight: 1.24,
          fontWeight: 500,
          letterSpacing: -2,
          whiteSpace: "pre-line",
        }}
      >
        {title}
      </div>
      <div
        style={{
          fontSize: 35,
          lineHeight: 1.7,
          opacity: 0.8,
          marginTop: 38,
          whiteSpace: "pre-line",
        }}
      >
        {body}
      </div>
    </Interactive.Div>
  );
};
export const Phone: React.FC<{
  file: string;
  x: number;
  y?: number;
  w?: number;
  angle?: number;
  delay?: number;
  video?: boolean;
}> = ({ file, x, y = 90, w = 410, angle = 0, delay = 10, video = false }) => {
  const f = useCurrentFrame();
  return (
    <Interactive.Div
      name="Unsplit native screen"
      style={{
        position: "absolute",
        left: x,
        top: y,
        width: w,
        padding: 5,
        borderRadius: 34,
        background: "linear-gradient(135deg,#fffefa,#9aa5a5,#eae7df)",
        boxShadow: "0 30px 65px #08252d45",
        opacity: interpolate(f, [delay, delay + 28], [0, 1], clamp),
        translate: interpolate(
          f,
          [delay, delay + 70],
          ["50px 35px", "0px 0px"],
          { ...clamp, easing: ease },
        ),
        rotate: interpolate(
          f,
          [0, 180, 540],
          [`${angle + 1}deg`, `${angle}deg`, `${angle - 0.5}deg`],
          { ...clamp, easing: ease },
        ),
      }}
    >
      <div style={{ overflow: "hidden", borderRadius: 29, lineHeight: 0 }}>
        {video ? (
          <Video
            src={media(file)}
            trimBefore={288}
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
export const DetailLine: React.FC<{
  items: string[];
  top?: number;
  dark?: boolean;
}> = ({ items, top = 810, dark = false }) => {
  const f = useCurrentFrame();
  return (
    <div
      style={{ position: "absolute", left: 112, top, display: "flex", gap: 46 }}
    >
      {items.map((s, i) => (
        <Interactive.Div
          name={s}
          key={s}
          style={{
            width: 245,
            paddingTop: 22,
            borderTop: `1px solid ${dark ? "#d5e3d775" : "#47616b55"}`,
            fontSize: 27,
            lineHeight: 1.6,
            whiteSpace: "pre-line",
            opacity: interpolate(f, [60 + i * 25, 90 + i * 25], [0, 1], clamp),
            translate: interpolate(
              f,
              [60 + i * 25, 110 + i * 25],
              ["0px 15px", "0px 0px"],
              { ...clamp, easing: ease },
            ),
          }}
        >
          {s}
        </Interactive.Div>
      ))}
    </div>
  );
};
