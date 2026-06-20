# WRO Future Engineers — Team APEX
<br/>

<div align="center">
  
<p align="center">
  <a href="#"><img src="https://img.shields.io/badge/WRO-Future%20Engineers-3B82F6?style=for-the-badge&logo=futurelearn&logoColor=white" alt="WRO Future Engineers"></a>
  <a href="#"><img src="https://img.shields.io/badge/Season-2026-22D3EE?style=for-the-badge" alt="Season 2026"></a>
  <a href="#-software-architecture"><img src="https://img.shields.io/badge/Language-Python_;_C++-FFD43B?style=for-the-badge&logo=python&logoColor=black" alt="Python"></a>
  <a href="#-software-architecture"><img src="https://img.shields.io/badge/Platform-Raspberry%20Pi_;_ESP32-A22846?style=for-the-badge&logo=raspberrypi&logoColor=white" alt="Raspberry Pi"></a>
  <a href="#-license"><img src="https://img.shields.io/badge/License-MIT-2EA44F?style=for-the-badge" alt="MIT License"></a>
</p>

<p align="center">
  <b>An autonomous, self-driving model car built for the World Robot Olympiad — Future Engineers category.</b><br>
  <sub>Computer-vision lane following · colour-based obstacle avoidance · IMU lap counting</sub>
</p>

<br/>

> *“The trick to having good ideas is not to sit around in glorious isolation and try to think big thoughts. The trick is to get more parts on the table.” – Steven Johnson*

<br/>

---
</div>

## Table of Contents

1. Overview  
&emsp;1.1 About APEX    
&emsp;1.2 Robot Images  
&emsp;1.3 Performance Video  

2. Mobility and Mechanical Design  
&emsp;2.1 Drivetrain  
&emsp;2.2 Steering Mechanism  
&emsp;2.3 Differential System  
&emsp;2.4 Chassis Design (Distribution; Aerodynamics)  
&emsp;2.5 Stability Improvement  

3. Power and Sensor Architecture  
&emsp;3.1 Power Source  
&emsp;3.2 Camera and Sensors  
&emsp;3.3 Dual Core System  
&emsp;3.4 Circuit Diagram  
&emsp;3.5 Power Consumption Modeling  

4. Software Architecture  
&emsp;4.1 Open Challenge  
&emsp;4.2 Obstacle Challenge  
&emsp;4.3 Parallel Parking  
&emsp;4.4 Code Structure   
&emsp;4.5 Instructions  

5. MathWorks® Modeling - SPARK Model  

6. Engineering Process - PRIMES Framework  

7. Building Instructions for Reproducibility  

8. Resources  
&emsp;8.1 3D CAD Models  
&emsp;8.2 List of Components  
&emsp;8.3 Suggestions for Further Development   

---

## The Team
We are a team of three enthusiastic students from **St. Paul’s College, Hong Kong**, participating in the World Robot Olympiad (WRO) Future Engineers category. United by our passion for robotics, innovation, and problem-solving, we strive to learn, collaborate, and break our limits in this international competition. We are proud to represent our school and look forward to competing and connecting with fellow robotics enthusiasts from around the world.

### Contributions
| Tin Shing Kwan, Amos | Tsang Kwok Cho, Hugo | Tsang Suen Hoi, Jasper |
| :---: | :---: | :---: |
| Mechanical Design, Circuit Design, 3D Modelling, Sensor Integration | Software Engineering, MathWorks® Modeling, Mechanical Improvement, Documentation | Wiring, Iteration and Testing, Logistics, Documentation |

---
## Overview

### About Team APEX

APEX is an ultra-compact autonomous vehicle engineered for exceptional speed, agility, and precision for the Future Engineers category. 

The vehicle incorporates a full Ackermann steering mechanism, a rear mechanical differential, and an active downforce system to optimise cornering performance and stability at high speeds. Inspired by the innovative Formula 1 car Brabham BT46B, APEX is designed to achieve remarkable cornering velocities, reflected in its name. 

A dual-core architecture combining an ESP32 and Raspberry Pi Zero 2W enables efficient task distribution: Python-based vision processing with the Pixy2 camera runs seamlessly alongside fast C++ control algorithms on the ESP32. Powered by a high-discharge 2S LiPo battery, APEX intelligently fuses data from dual Time-of-Flight (ToF) sensors and an IMU to deliver precise navigation, reliable obstacle handling, and automated parallel parking.

> [!NOTE]
> ## Specialties
> 
> **Downforce Generation System**
>
> APEX features an innovative active downforce generation system designed to enhance stability and cornering performance at high speeds. The system > employs strategically placed aerodynamic elements that create downward pressure, improving traction and minimising slippage during sharp turns on > the WRO track.
> 
> **Hybrid Snap-to-Fit and Screwed-in Design**
> 
> A hybrid snap-to-fit and screwed-in design philosophy was adopted for the chassis and body components. This modular approach enables rapid
> prototyping, easy maintenance, and quick repairs during competition iterations. By minimising the number of screws, we significantly reduced 
> overall weight and mechanical complexity while preserving structural integrity. Critical components such as the motors and steering servo are
> securely screwed in place to provide maximum stability and vibration resistance under high-speed operation.
>
> **Dual-Processor Architecture**
>
> Our perception pipeline and control logic utilise a robust dual-processor architecture that intelligently splits workloads to ensure high-speed
> computer vision processing never compromises the deterministic and real-time requirements of driving control. In this system, a Raspberry Pi Zero
> 2W is dedicated to advanced Python-based vision processing using the Pixy2 camera, performing real-time line tracking, occupancy grid mapping
> and coloured pillar detection. Meanwhile, the ESP32-S3 executes a deterministic state machine and control algorithms in C++ for instantaneous
> motor control, sensor fusion (IMU and dual ToF sensors), and low-level PID regulation. This separation of concerns delivers both computational
> efficiency and reliable real-time performance.

### Robot Images

Six required views of APEX. _(Placeholders — drop your real photos into [`v-photos/`](./v-photos).)_

<br/>

<table>
  <tr>
    <td><img src="./v-photos/front.svg" alt="Front view" width="100%"></td>
    <td><img src="./v-photos/back.svg" alt="Back view" width="100%"></td>
    <td><img src="./v-photos/left.svg" alt="Left view" width="100%"></td>
  </tr>
  <tr>
    <td align="center"><sub>Front</sub></td><td align="center"><sub>Back</sub></td><td align="center"><sub>Left</sub></td>
  </tr>
  <tr>
    <td><img src="./v-photos/right.svg" alt="Right view" width="100%"></td>
    <td><img src="./v-photos/top.svg" alt="Top view" width="100%"></td>
    <td><img src="./v-photos/bottom.svg" alt="Bottom view" width="100%"></td>
  </tr>
  <tr>
    <td align="center"><sub>Right</sub></td><td align="center"><sub>Top</sub></td><td align="center"><sub>Bottom</sub></td>
  </tr>
</table>

<br/>

### Performance Video

<div align="center">

[![Demo Video](https://img.shields.io/badge/▶%20Watch%20Demo-YouTube-FF0000?style=for-the-badge&logo=youtube)](https://youtu.be/REPLACE_WITH_VIDEO_ID)

</div>

> See `link` for the direct link to our driving demonstration on YouTube (minimum 30 seconds of autonomous driving per competition rules).

---
## Mobility and Mechanical Design

### 2.1 Drivetrain  

### 2.2 Steering Mechanism  

### 2.3 Differential System  

### 2.4 Chassis Design (Distribution; Aerodynamics)  

### 2.5 Stability Improvement

---

## Power and Sensor Architecture  

### 3.1 Power Source  

### 3.2 Camera and Sensors  

### 3.3 Dual Core System  

### 3.4 Circuit Diagram  

### 3.5 Power Consumption Modeling 

---

## Software Architecture  

### 4.1 Open Challenge  

### 4.2 Obstacle Challenge  

### 4.3 Parallel Parking  

### 4.4 Code Structure   

### 4.5 Instructions  

---

## MathWorks® Modeling - SPARK Model  

---

## Engineering Process - PRIMES Framework  

The PRIMES Framework is our overarching, model-based systems engineering workflow for the entire WRO project. It defines how we approach the full development lifecycle — from initial concept and mechanical design through to control implementation, testing, optimization, and final validation.

At its core, PRIMES enforces a disciplined, iterative process that deeply integrates MATLAB, Simulink, and Simscape throughout every stage of engineering. Simulation is not an afterthought or simple graphing tool; it is a primary driver of design decisions, risk reduction, and performance improvement.

**Core Philosophy**
Model → Simulate → Validate against real hardware → Iterate.
What PRIMES Stands For
- Prototype Create high-fidelity digital prototypes (plant models, controllers, sensor systems, and powertrain) using MATLAB/Simulink/Simscape before committing to physical hardware.
- Refine Use simulation to rapidly explore design alternatives, optimize parameters, and test scenarios that would be difficult or time-consuming to evaluate physically.
- Integrate Seamlessly bridge virtual models with real-world components through Hardware-in-the-Loop (HIL) testing, Embedded Coder code generation, and real-time interfaces.
- Measure Collect detailed performance data from the physical vehicle and test setups, then quantitatively compare it against simulation results to validate model accuracy.
- Evaluate Analyze results, identify gaps between simulation and reality, assess key metrics (lap time, stability, energy efficiency, sensor reliability, etc.), and determine root causes of discrepancies.
- Systematize (Iterate) Formalize lessons learned, update models/mechanical designs/controllers, and systematically iterate through the cycle until targets are achieved.

**Application Across the Project**
We applied the PRIMES framework holistically across all aspects of development:
- Mechanical design and vehicle dynamics
- Electrical and powertrain systems
- Control algorithms (PID speed & steering)
- Computer vision and sensor processing (Pixy2)
- Energy efficiency analysis
- Lap time optimization and parametric studies
- Overall system integration and track testing

This structured approach enabled strong correlation between virtual predictions and actual performance, minimized physical prototyping iterations, and allowed data-driven decisions throughout the project.

--- 

## Building Instructions for Reproducibility  

---

## Resources  

### 8.1 3D CAD Models  

### 8.2 List of Components  

### 8.3 Suggestions for Further Development  

---

## Acknowledgement

We would like to express our sincere gratitude to everyone who supported us throughout this challenging yet rewarding journey. 

We are especially thankful to **Mr. H. T. Tsui** for providing patient guidance, tireless support during countless debugging sessions, and constantly inspiring us to push beyond our limits. 

We extend our deep appreciation to **St. Paul's College** for generously providing dedicated workspace, access to essential equipment, and logistical travel support that enabled us to participate in the competition. 

Our heartfelt thanks go to the **WRO Association** for organising this remarkable international competition that continues to drive innovation and engineering excellence among students worldwide. 

Finally, we acknowledge the invaluable contributions of the **open-source community**, including the developers of OpenCV, Python, the Raspberry Pi Foundation, PixyCam, and all other libraries and tools whose collective efforts have powerfully supported the realisation of our autonomous vehicle.

---

</div>

## License

Released under the **MIT License** — see [`LICENSE`](./LICENSE). Learn from and build on APEX freely. A mention back to **Team APEX** is always appreciated. 

</div>

---

<div align="center">

**Built with curiosity, simulation, and a lot of testing by Team APEX**

*WRO Future Engineers · Season 2026 · Hong Kong*

[![WRO](https://img.shields.io/badge/World%20Robot%20Olympiad-Future%20Engineers-0066CC?style=flat-square)](https://wro-association.org/competition/future-engineers/)
[![GitHub](https://img.shields.io/badge/GitHub-WRO2026_FE_Apex-181717?style=flat-square&logo=github)](https://github.com/HT-alpha/WRO-Internal)

</div>
