# WRO 2026 Future Engineers — Team APEX
</div>

## Table of Contents

1. [Overview](https://github.com/wro26-teamapex/WRO2026_FE_Apex#1-overview)    
&emsp;1.1 [About APEX](https://github.com/wro26-teamapex/WRO2026_FE_Apex#about-apex)  
&emsp;1.2 [Specialties](https://github.com/wro26-teamapex/WRO2026_FE_Apex#specialties)  
&emsp;1.2 [Robot Images](https://github.com/wro26-teamapex/WRO2026_FE_Apex#robot-images)  
&emsp;1.3 [Performance Videos](https://github.com/wro26-teamapex/WRO2026_FE_Apex#performance-videos)  

3. Mobility and Mechanical Design  
&emsp;2.1 Chassis Design  
&emsp;2.2 Powertrain  
&emsp;2.3 Steering Mechanism  
&emsp;2.4 Stability Improvements  


4. Power and Sensor Architecture  
&emsp;3.1 Power Source  
&emsp;3.2 Camera and Sensors  
&emsp;3.3 Dual Core System  
&emsp;3.4 Circuit Diagram  
&emsp;3.5 Power Consumption Modeling  

5. Software Architecture  
&emsp;4.1 Open Challenge  
&emsp;4.2 Obstacle Challenge  
&emsp;4.3 Parallel Parking  
&emsp;4.4 Code Structure   
&emsp;4.5 Instructions  

6. MathWorks® Modeling - SPARK Model  

7. Engineering Process - PRIMES Framework  

8. Building Instructions for Reproducibility  

9. Resources  
&emsp;8.1 3D CAD Models  
&emsp;8.2 List of Components  
&emsp;8.3 Suggestions for Further Development   

---
>[!NOTE]
>**This repo contains generalized buttons, which provide extra details regarding the design of APEX.**  
>
>[![Design Evaluation](https://img.shields.io/badge/▟%20Design%20Evaluation-CC540E?style=for-the-badge&logo=)](link)  
>🞙 Discussion on pros & cons of the design, comparison with other applicable methods  
>
>[![In Depth Calculations](https://img.shields.io/badge/In%20Depth%20Calculations-2A8011?style=for-the-badge&logo=pulumi)](link)  
>🞙 Detailed calculations regarding the topic  
>
>[![Components List](https://img.shields.io/badge/Components%20List-114580?style=for-the-badge&logo=agentskills)](link)  
>🞙 Components checklist for the specific section  


---

## The Team
We are a team of three enthusiastic students from **St. Paul’s College, Hong Kong**, participating in the World Robot Olympiad (WRO) Future Engineers category. United by our passion for robotics, innovation, and problem-solving, we strive to learn, collaborate, and break our limits in this international competition. We are proud to represent our school and look forward to competing and connecting with fellow robotics enthusiasts from around the world.

### Contributions
| Tin Shing Kwan, Amos | Tsang Kwok Cho, Hugo | Tsang Suen Hoi, Jasper |
| :---: | :---: | :---: |
| Mechanical Design, Circuit Design, 3D Modelling, Sensor Integration | Software Engineering, MathWorks® Modeling, Mechanical Improvement, Documentation | Wiring, Iteration and Testing, Logistics, Documentation |

---
## 1. Overview
>### About APEX
>APEX is an ultra-compact autonomous vehicle engineered for exceptional speed, agility, and precision for the Future Engineers category.
>
>The vehicle incorporates a full Ackermann steering mechanism, a rear mechanical differential, and an active downforce system to optimise cornering performance and stability at high speeds. Inspired by the innovative Formula 1 car Brabham BT46B, APEX is designed to achieve remarkable cornering velocities, reflected in its name.
>
>A dual-core architecture combining an ESP32 and Raspberry Pi Zero 2W enables efficient task distribution: Python-based vision processing with the Pixy2 camera runs seamlessly alongside fast C++ control algorithms on the ESP32. Powered by a high-discharge 2S LiPo battery, APEX intelligently fuses data from dual Time-of-Flight (ToF) sensors and an IMU to deliver precise navigation, reliable obstacle handling, and automated parallel parking.

### Specialties

🞙 **Downforce Generation System**  
The active downforce generation system utilizes a fan to create a vacuum at the belly of the car, creating constant downforce which improves grip and minimises skidding, allowing the car to
move at much higher speeds during turns.  
[In-depth explanation in Section 2.5](https://github.com/wro26-teamapex/WRO2026_FE_Apex/edit/main/README.md#25-stability-improvement)

🞙 **Hybrid Fitting Design**  
APEX adopts snap-to-fit designs for most chassis plastic components, while using hex and nut bearings to fixate motors. The snap to fit design allows layers of the chassis to be replaced
swiftly, hence faster repairs and prototyping. On the contrary, hex and nut provide great stability for dynamic components such as motors.  
[In-depth explanation in Section 2.4](https://github.com/wro26-teamapex/WRO2026_FE_Apex/edit/main/README.md#24-chassis-design-distribution-aerodynamics)

🞙 **Heterogeneous Architecture**  
Our dual MCU design splits workloads cleanly to minimise delays. The Raspberry Pi Zero 2W processes vision and navigation, while the Arduino Nano ESP32 manages sensor and motor control.  
[In-depth explanation in Section 3.3](https://github.com/wro26-teamapex/WRO2026_FE_Apex/edit/main/README.md#24-chassis-design-distribution-aerodynamics)


### Robot Images

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

### Performance Videos

[![Demo Video](https://img.shields.io/badge/Introductory-FF0000?style=for-the-badge&logo=youtube)](https://youtu.be/REPLACE_WITH_VIDEO_ID)
[![Demo Video](https://img.shields.io/badge/Open%20Challenge-FF0000?style=for-the-badge&logo=youtube)](https://youtu.be/REPLACE_WITH_VIDEO_ID)
[![Demo Video](https://img.shields.io/badge/Obstacle%20Challenge-FF0000?style=for-the-badge&logo=youtube)](https://youtu.be/REPLACE_WITH_VIDEO_ID)

---
## 2. Mobility and Mechanical Design

### 2.1 Chassis Design
<details>
<summary>General Specifications</summary>

---

&emsp;**Dimensions:** 115mm (L) x 80mm (W) x 105mm (H)  

&emsp;**Total Mass:** Xg  

&emsp;**3D printing material:** PETG, Nylon  

&emsp;**Drive configuration:** Front wheel steering, rear wheel drive  

---
</details>

<details>
<summary>Vehicle Structure</summary>

---

&emsp;APEX is divided into six vital parts, each part having its respective function.  

<table align="center" border="0">
  <tr>
    <td align="center"><img src="fig(2.1.1).png" width="400px" /></td>
    <td align="center"><img src="fig(2.1.2).png" width="400px" /></td>
  </tr>
  <tr>
    <td align="center"><b>Fig 2.1.1 </b>Chassis Function Distribution (Side) </td>
    <td align="center"><b>Fig 2.1.2 </b>Chassis Function Distribution (Bottom) </td>
  </tr>
</table>

&emsp;🞙 $\color{#ff5252}\mathbf{\mathsf{STEERING}}$ - Redirects the vehicle’s trajectory  
&emsp;🞙 $\color{#ff9452}\mathbf{\mathsf{ELECTRONICS\ COMPARTMENT}}$ - Houses most of the car’s sensors and electronics  
&emsp;🞙 $\color{#ffd452}\mathbf{\mathsf{ACTIVE\ DOWNFORCE}}$ - Creates a vacuum at the vehicle's belly  
&emsp;🞙 $\color{#64d941}\mathbf{\mathsf{POWERTRAIN}}$ - Propels the car forward  
&emsp;🞙 $\color{#4d95e8}\mathbf{\mathsf{BATTERY\ COMPARTMENT}}$ - Sole electricity supplier for all car components  
&emsp;🞙 $\color{#9d4de8}\mathbf{\mathsf{VISION\ PROCESSING\ AREA}}$ - Captures and analyses vision  

---
</details>

<details>
<summary>Hybrid Fitting Design</summary>

---

&emsp;A hybrid fastening strategy for the vehicle components was engineered, combining simple snap-to-fit joints and screw-and-nut assemblies &emsp;to secure structural components.  

<table align="center" border="0">
  <tr>
    <td align="center"><img src="fig(2.1.3).gif" width="400px" /></td>
    <td align="center"><img src="fig(2.1.4).gif" width="400px" /></td>
  </tr>
  <tr>
    <td align="center"><b>Fig 2.1.3 </b>Snap-to-fit joint example</td>
    <td align="center"><b>Fig 2.1.4 </b>Screw-and-nut assembly example</td>
  </tr>
</table>

&emsp;Static components (e.g. most of the chassis components) are fixated via snap-to-fit joints.  
&emsp;They include a 0.1mm buffer gap on every side to allow minimal 3D printing errors.   
&emsp;Dynamic components (e.g. servo motor & N20 motor) are fixated via screw-and-nut assemblies.  

&emsp;[![Design Evaluation](https://img.shields.io/badge/▟%20Design%20Evaluation-CC540E?style=for-the-badge&logo=)](link)

---
</details>

### 2.2 Powertrain  
<details>
<summary>Rear propulsion</summary>

---

&emsp;Rear propulsion of APEX is driven by an N20 gear motor [] equipped with an integrated encoder for precise feedback. Rotational torque is  
&emsp;transferred 90° via a perpendicular pair of custom nylon-printed miter gears []. The bevel gear is coupled to the differential case, which  
&emsp;distributes mechanical power to both d-shafts [] while allowing independent wheel rotation, eliminating skidding during cornering.

<table align="left" border="0">
  <tr>
    <td align="left"><img src="fig(2.2.1).png" width="400px" /></td>
  </tr>
  <tr>
    <td align="left"><b>Fig 2.2.1 </b>Powertrain Components Diagram</td>
  </tr>
</table>  
<br clear="left"/>

&emsp;How is rotational power transferred?  

&emsp;1. N20 motor rotates the pinion gear  
&emsp;2. The pinion gear rotates the bevel gear, angle shifted 90° clockwise  
&emsp;3. The attached differential case rotates along the d-shaft  
&emsp;4. The differential’s planet and sun gears distribute torque to both shafts  
&emsp;5. The shafts rotate the wheel  

<table align="left" border="0">
  <tr>
    <td align="left"><img src="fig(2.2.2).png" width="400px" /></td>
  </tr>
  <tr>
    <td align="left"><b>Fig 2.2.2 </b>Power Transfer Diagram</td>
  </tr>
</table>  
<br clear="left"/>

---
</details>

<details>
<summary>The differential</summary>

---

&emsp;Composed of 1x bevel gear [], 1x differential case [], 2x spider gears [] and 2x side gears [], it is one of the two measures (the other being full  
&emsp;Ackermann steering, mentioned in Section 2.3) we opted to eliminate tire scrubbing, which improves movement accuracy.

<table align="left" border="0">
  <tr>
    <td align="left"><img src="fig(2.2.3).png" width="400px" /></td>
  </tr>
  <tr>
    <td align="left"><b>Fig 2.2.3 </b>Differential Structure Diagram</td>
  </tr>
</table>  
<br clear="left"/>

---
</details>

[![Components List](https://img.shields.io/badge/Components%20List-114580?style=for-the-badge&logo=agentskills)](link)  

### 2.3 Steering Mechanism  

### 2.4 Stability Improvements

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
