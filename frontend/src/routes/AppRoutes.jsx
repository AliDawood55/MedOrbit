import {
    BrowserRouter,
    Routes,
    Route
} from "react-router-dom";


import Login from "../pages/auth/Login";
import Register from "../pages/auth/Register";
import ForgotPassword from "../pages/auth/ForgotPassword";
import ResetPassword from "../pages/auth/ResetPassword";
import VerifyEmail from "../pages/auth/VerifyEmail";
import ProtectedRoute from "./ProtectedRoute";

// Temporary pages for testing
function DoctorDashboard() {

    return <h1>Doctor Dashboard</h1>;

}


function PatientDashboard() {

    return <h1>Patient Dashboard</h1>;

}


function AdminDashboard() {

    return <h1>Admin Dashboard</h1>;

}


function Unauthorized() {

    return <h1>403 - Unauthorized</h1>;

}




function AppRoutes() {


    return (

        <BrowserRouter>

            <Routes>


                <Route
                    path="/login"
                    element={<Login />}
                />


                <Route
                    path="/register"
                    element={<Register />}
                />


                <Route
                    path="/forgot-password"
                    element={<ForgotPassword />}
                />

                <Route

                    path="/reset-password"

                    element={<ResetPassword />}

                />


                <Route

                    path="/verify-email"

                    element={<VerifyEmail />}

                />

                <Route

                    path="/doctor/dashboard"

                    element={

                        <ProtectedRoute roles={["doctor"]}>

                            <DoctorDashboard />

                        </ProtectedRoute>

                    }

                />

                {/* Protected Patient Route */}

                <Route

                    path="/patient/dashboard"

                    element={

                        <ProtectedRoute roles={["patient"]}>

                            <PatientDashboard />

                        </ProtectedRoute>

                    }

                />



                {/* Protected Admin Route */}

                <Route

                    path="/admin/dashboard"

                    element={

                        <ProtectedRoute roles={["admin"]}>

                            <AdminDashboard />

                        </ProtectedRoute>

                    }

                />



                <Route

                    path="/unauthorized"

                    element={<Unauthorized />}

                />



            </Routes>


        </BrowserRouter>

    );


}


export default AppRoutes;